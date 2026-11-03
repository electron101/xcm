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

/// Generate UUID v4 in format: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
/// https://www.rfc-editor.org/rfc/rfc9562.html
pub fn randomUUIDv4(io: std.Io, buf: *[36]u8) void {
    var bytes: [16]u8 = undefined;
    const rng: std.Random.IoSource = .{ .io = io };
    rng.interface().bytes(&bytes);

    //
    // Set version and variant:
    // 00000000-0000-4000-8000-000000000000
    //
    // More info:
    // https://www.rfc-editor.org/rfc/rfc9562.html#name-version-field
    // https://www.rfc-editor.org/rfc/rfc9562.html#name-variant-field
    //
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version = 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant = 10xx

    const hex = "0123456789abcdef";
    var i: usize = 0;
    var j: usize = 0;
    while (i < 16) : (i += 1) {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            buf[j] = '-';
            j += 1;
        }
        buf[j] = hex[bytes[i] >> 4];
        buf[j + 1] = hex[bytes[i] & 0x0f];
        j += 2;
    }
}

pub fn isValidJsonStringContent(str: []const u8) bool {
    for (str) |c| {
        switch (c) {
            '"', '\\' => return false,

            // All codes from 0x00–0x1F are control characters (non-printable)
            else => if (c < 0x20) return false,
        }
    }
    return true;
}
