const std = @import("std");

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
pub fn writeStdout(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const slice = std.mem.print(&buf, fmt, args) catch return;
    writeAllFd(std.posix.STDOUT_FILENO, slice);
}

