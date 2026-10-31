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

fn readAllFd(fd: std.posix.fd_t, buf: []u8) ?usize {
    var total: usize = 0;
    while (total < buf.len) {
        const rc = std.os.linux.read(fd, buf[total..].ptr, buf.len - total);
        switch (std.os.linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0)
                    return if (total == 0) null else total; // EOF
                total += rc;
                // Stop reading once a newline appears in the buffer.
                if (std.mem.indexOfScalar(u8, buf[0..total], '\n')) |_| {
                    return total;
                }
            },
            .INTR => continue,
            else => return null,
        }
    }
    return total; // buf is fill, \n not found
}

/// Reads up to `buf.len` bytes from stdin, stopping after a read containing `\n` or at EOF.
/// Returns a slice into `buf`, with a trailing `\n` and optional `\r` removed.
/// Returns null if no bytes were read or a read error occurred.
pub fn readStdinLine(buf: []u8) ?[]u8 {
    const n = readAllFd(std.posix.STDIN_FILENO, buf) orelse return null;
    var line = buf[0..n];

    // delete \n and \r in the end
    if (line.len > 0 and line[line.len - 1] == '\n') {
        line = line[0 .. line.len - 1];
    }
    if (line.len > 0 and line[line.len - 1] == '\r') {
        line = line[0 .. line.len - 1];
    }
    return line;
}
