// TODO:
//
// 1. add user
//
// 2. delete user
//
// 3. show user (id, vless link, qr???)
//
// 4. add Global Menu as:
//    > ...
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
const writeStdout = @import("utils.zig").writeStdout;
const readStdinLine = @import("utils.zig").readStdinLine;
const randomUUIDv4 = @import("utils.zig").randomUUIDv4;
const isValidJsonStringContent = @import("utils.zig").isValidJsonStringContent;
const vless_clients = @import("clients.zig");
const Client = @import("clients.zig").Client;

const version = "0.0";
const default_xray_config_path = "/usr/local/etc/xray/config.json";

fn saveConfig(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    org_config_filename: []const u8,
    root: std.json.Value,
) !void {
    const json_text = try std.json.Stringify.valueAlloc(
        allocator,
        root,
        .{ .whitespace = .indent_2 },
    );
    defer allocator.free(json_text);

    std.log.debug("saveConfig(): org_config_filename: {s}", .{org_config_filename});

    // Use a timestamp to avoid overwriting previous backups.
    const timestamp_ns = std.Io.Timestamp.now(io, .real).toNanoseconds();
    const backup_name = try std.fmt.allocPrint(
        allocator,
        "{s}.backup.{d}",
        .{ org_config_filename, timestamp_ns },
    );
    defer allocator.free(backup_name);

    // TODO: Validate the generated config before modifying the original.
    // Consider running: xray run -test -config <temp_config_path>

    var new_config_file = try dir.createFileAtomic(
        io,
        org_config_filename,
        .{ .replace = true },
    );
    defer new_config_file.deinit(io);

    try new_config_file.file.writeStreamingAll(io, json_text);
    try new_config_file.file.sync(io);

    // Move the original config to a backup before installing the new one.
    try dir.renamePreserve(org_config_filename, dir, backup_name, io);

    // Install the new config. Restore the backup if replacement fails.
    new_config_file.replace(io) catch |err| {
        dir.renamePreserve(backup_name, dir, org_config_filename, io) catch {
            return error.BackupRestoreFailed;
        };
        return err;
    };
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

    var buf: [256]u8 = undefined;
    while (true) {
        writeStdout(
            \\ menu:
            \\ n) New user
            \\ d) Delete user
            \\ l) List all users
            \\ q) Quit
            \\
            \\ n/d/l/q> 
        , .{});

        if (readStdinLine(&buf)) |line| {
            writeStdout("You input: \"{s}\"\n", .{line});
            if (std.mem.eql(u8, line, "q") or std.mem.eql(u8, line, "quit")) {
                writeStdout("Exit ... \n", .{});
                return;
            } else if (std.mem.eql(u8, line, "n")) {
                // UUID
                var uuid: [36]u8 = @splat(0);
                randomUUIDv4(io, &uuid);

                // Email
                var email_buf: [256]u8 = undefined;
                var email: []const u8 = undefined;
                while (true) {
                    writeStdout("user name (email)> ", .{});

                    email = readStdinLine(&email_buf) orelse "";
                    if (isValidJsonStringContent(email))
                        break;
                }
                email = if (email.len == 0) "default" else email;

                const new_client: Client = .{
                    .id = try allocator.dupe(u8, &uuid),
                    .email = try allocator.dupe(u8, email),
                    .flow = "xtls-rprx-vision",
                };

                vless_clients.addClient(allocator, &parsed.value, "vless", new_client) catch |err| {
                    switch (err) {
                        error.DuplicateClientId => {
                            writeStdout("This user alredy exist! \n", .{});
                            continue;
                        },
                        else => return,
                    }
                };

                try saveConfig(allocator, init.io, std.Io.Dir.cwd(), xray_config_path, parsed.value);
            } else if (std.mem.eql(u8, line, "d")) {
                writeStdout("not impl yet \n", .{});
            } else if (std.mem.eql(u8, line, "l")) {
                const clients = try vless_clients.getClients(
                    allocator,
                    parsed.value,
                    "vless",
                );
                defer allocator.free(clients);

                for (clients, 0..) |client, i| {
                    std.log.debug(
                        "  Client [{d}]: email={s}, id={s}, flow={s}\n",
                        .{ i, client.email, client.id, client.flow },
                    );
                }
            }
        } else {
            writeStdout("EOF or error \n", .{});
        }
    }
}
