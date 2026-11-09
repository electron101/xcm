const std = @import("std");

const debug_log = false;

pub const Client = struct {
    id: []const u8,
    email: []const u8,
    flow: []const u8,
};

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

pub fn addClient(
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

pub fn getClients(
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

        if (debug_log) {
            std.log.debug(
                "\nInbound [{d}]: tag={s}, protocol={s}\n",
                .{ index, tag, protocol },
            );
        }

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

            if (debug_log) {
                std.log.debug(
                    "  Client [{d}]: email={s}, id={s}, flow={s}\n",
                    .{ client_index, email, id, flow },
                );
            }

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

pub fn getClientByNum(
    root: *std.json.Value,
    target_protocol: []const u8,
    target_num: u32,
) !Client {
    const clients = try findClientsArray(root, target_protocol);

    for (clients.items, 0..) |item, i| {
        if (target_num == i) {
            return .{
                .id = getString(item, "id") orelse continue,
                .email = getString(item, "email") orelse continue,
                .flow = "",
            };
        }
    }
    return error.ClientNotFound;
}

pub fn deleteClient(
    allocator: std.mem.Allocator,
    root: *std.json.Value,
    target_protocol: []const u8,
    target_uuid: []const u8,
) !void {
    const clients = try findClientsArray(root, target_protocol);

    for (clients.items, 0..) |item, i| {
        const id = getString(item, "id") orelse continue;
        if (std.mem.eql(u8, id, target_uuid)) {
            std.log.debug("Client #{d} - {s} will be removed.\n", .{ i, id });
            // Remove the client from the array.
            var removed = clients.orderedRemove(i);

            // Free the removed JSON object's allocated memory.
            removed.object.deinit(allocator);

            return;
        }
    }
    return error.ClientNotFound;
}
