// TODO:
//
// 1. add user
//
// 2. delete user
//
// 3. show user (id, vless link, qr???)
//
//
// "clients": [
// {
//   "email": "main",
//   "id": "718c0837-6f83-4242-ae23-cfe07b81c1db",
//   "flow": "xtls-rprx-vision"
// },
//
//
//
// vless://84ab3c1e-173d-4de2-a15b-0567bf4d9372@140.235.130.61:7443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=myw9aQ1coOiGU3WXAvoDIVsgQ-_n1gvbdZLcYf30y2I&sid=e62317ec29decdc7&type=tcp#cudy-fr69
//

const std = @import("std");

const Client = struct {
    id: []const u8,
    email: []const u8,
    flow: []const u8,
};

const version = "0.0";
const default_xray_config_path = "/usr/local/etc/xray/config.json";

fn writeAllFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = std.os.linux.write(fd, bytes[written..].ptr, bytes.len - written);
        switch (std.os.linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return;
                written += rc;
            },
            .INTR => continue,
            else => return,
        }
    }
}

/// Write a formatted string to stdout via posix write.
fn writeStdout(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const slice = std.mem.print(&buf, fmt, args) catch return;
    writeAllFd(std.posix.STDOUT_FILENO, slice);
}

fn getString(value: std.json.Value, key: []const u8) ?[]const u8 {
    if (value != .object)
        return null;

    const field = value.object.get(key) orelse return null;
    if (field != .string)
        return null;

    return field.string;
}

fn findClientsArray(
    root: *std.json.Value,
    target_protocol: []const u8,
) !*std.json.Array {
    if (root.* != .object)
        return error.InvalidConfigRoot;

    const inbounds = root.object.getPtr("inbounds") orelse
        return error.MissingInbound;

    if (inbounds.* != .array)
        return error.InvalidInbounds;

    for (inbounds.array.items) |*inbound| {
        if (inbound.* != .object)
            continue;

        const protocol = getString(inbound.*, "protocol") orelse continue;

        if (!std.mem.eql(u8, protocol, target_protocol)) {
            // std.log.debug("protocol = {s} not target", .{protocol});
            continue;
        }

        const settings = inbound.object.getPtr("settings") orelse
            return error.MissingSettings;

        if (settings.* != .object)
            return error.InvalidSettings;

        const clients = settings.object.getPtr("clients") orelse
            return error.MissingClients;

        return &clients.array;
    }

    return error.InboundsNotFound;
}

fn addClient(
    alloc: std.mem.Allocator,
    root: *std.json.Value,
    target_protocol: []const u8,
    client: Client,
) !void {
    const clients = try findClientsArray(root, target_protocol);

    for (clients.items) |item| {
        const id = getString(item, "id") orelse continue;
        if (std.mem.eql(u8, id, client.id)) {
            return error.DuplicateClientId;
        }
    }

    var obj: std.json.ObjectMap = .empty;
    errdefer obj.deinit(alloc);

    try obj.put(alloc, "id", .{ .string = client.id });
    try obj.put(alloc, "email", .{ .string = client.email });
    try obj.put(alloc, "flow", .{ .string = client.flow });

    try clients.append(.{ .object = obj });
}

fn getClients(
    alloc: std.mem.Allocator,
    root: std.json.Value,
    target_protocol: []const u8,
) ![]Client {
    if (root != .object)
        return error.InvalidConfigRoot;

    const inbounds_value = root.object.get("inbounds") orelse return error.MissingInbound;

    if (inbounds_value != .array)
        return error.InvalidInbounds;

    for (inbounds_value.array.items, 0..) |inbound, index| {
        if (inbound != .object)
            continue;

        const tag = getString(inbound, "tag") orelse "(not tag)";
        const protocol = getString(inbound, "protocol") orelse "(unknow)";

        std.log.debug(
            "\nInbound [{d}]: tag={s}, protocol={s}\n",
            .{ index, tag, protocol },
        );

        if (!std.mem.eql(u8, protocol, target_protocol)) {
            std.log.debug("protocol = {s} not target", .{protocol});
            continue;
        }

        const settings = inbound.object.get("settings") orelse return error.MissingSettings;
        if (settings != .object)
            continue;

        const clients_value = settings.object.get("clients") orelse return error.MissingClients;
        if (clients_value != .array)
            continue;

        var clients: std.ArrayList(Client) = .empty;
        errdefer clients.deinit(alloc);

        for (clients_value.array.items, 0..) |client, client_index| {
            if (client != .object)
                continue;

            const id = getString(client, "id") orelse "(no id)";
            const email = getString(client, "email") orelse "(no email)";
            const flow = getString(client, "flow") orelse "(no flow)";

            std.log.debug(
                "  Client [{d}]: email={s}, id={s}, flow={s}\n",
                .{ client_index, email, id, flow },
            );

            try clients.append(alloc, .{
                .id = id,
                .email = email,
                .flow = flow,
            });
        }
        return try clients.toOwnedSlice(alloc);
    }
    return error.ClientsNotFound;
}

fn saveConfig(
    allocator: std.mem.Allocator,
    io: std.Io,
    config_path: []const u8,
    root: std.json.Value,
) !void {
    const json_text = try std.json.Stringify.valueAlloc(
        allocator,
        root,
        .{ .whitespace = .indent_2 },
    );
    defer allocator.free(json_text);

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = config_path,
        .data = json_text,
    });
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const allocator = arena.allocator();
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();

    const prog_name = args.next(); // skip program name
    const first_arg = args.next();

    // Parse Xray config path from args
    if (first_arg) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            writeStdout(
                \\ 
                \\ Usage: {s} [config.json]
                \\ 
                \\ Default Xray config at {s}
                \\ 
                \\ Options:
                \\   -h, --help         Show this help message and exit
                \\   -v, --version      Show version and exit
                \\
                \\
            , .{ prog_name.?.ptr, default_xray_config_path });
            return;
        }
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            writeStdout("{s}\n", .{version});
            return;
        }
    }

    const xray_config_path = first_arg orelse default_xray_config_path;
    writeStdout("I'll use this Xray config file: {s}\n", .{xray_config_path});

    const json_content = try std.Io.Dir.cwd().readFileAlloc(
        io,
        xray_config_path,
        allocator,
        .limited(1024 * 1024), // 1 MB
    );
    defer allocator.free(json_content);

    // std.debug.print("Xray json:\n{s}\n", .{json_content});

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_content,
        .{},
    );
    defer parsed.deinit();

    // std.debug.print("Xray json(parsed):\n{any}\n", .{parsed});

    const new_client: Client = .{
        .id = "11111111-1111-4111-8111-111111111111",
        .email = "alice",
        .flow = "xtls-rprx-vision",
    };

    try addClient(allocator, &parsed.value, "vless", new_client);

    const clients = try getClients(allocator, parsed.value, "vless");
    defer allocator.free(clients);

    for (clients, 0..) |client, i| {
        std.log.debug(
            "  Client [{d}]: email={s}, id={s}, flow={s}\n",
            .{ i, client.email, client.id, client.flow },
        );
    }

    try saveConfig(allocator, init.io, "config.json", parsed.value);
}
