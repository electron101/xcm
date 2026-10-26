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

// const XrayConf = struct {
//     ip
// };

const Clients = struct {
    id: []const u8,
    email: []const u8,
    flow: []const u8,
};

const std = @import("std");

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

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
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

    std.debug.print("Xray json:\n{s}\n", .{json_content});

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_content,
        .{},
    );
    defer parsed.deinit();

    std.debug.print("Xray json(parsed):\n{any}\n", .{parsed});
}
