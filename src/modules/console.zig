//! Console is used for serial output and formatted printing.

const std = @import("std");
const uart = @import("../arch/aarch64/uart.zig");

pub const name = "console";

pub const truncation_marker = "...\n";

pub fn init() !void {
    uart.write("Hello from Korbora\n");
}

/// Format fmt with args into buf.
/// If the formatted output exceeds buf, truncates safely with truncation_marker
/// and never returns uninitialized bytes.
pub fn format(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    if (buf.len == 0) return buf[0..0];

    var w: std.Io.Writer = .fixed(buf);

    if (w.print(fmt, args)) |_| {
        return w.buffered();
    } else |_| {
        const written = w.buffered().len;

        if (buf.len >= truncation_marker.len) {
            const start = @min(written, buf.len - truncation_marker.len);
            @memcpy(buf[start .. start + truncation_marker.len], truncation_marker);
            return buf[0 .. start + truncation_marker.len];
        }

        return buf[0..written];
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const s = format(&buf, fmt, args);

    uart.write(s);
}

pub fn write(s: []const u8) void {
    uart.write(s);
}

const testing = std.testing;

test "console: format basic types" {
    var buf: [64]u8 = undefined;
    const s = format(&buf, "num={d} str={s} hex=0x{x}", .{ 42, "korbora", 0xabcd });

    try testing.expectEqualStrings("num=42 str=korbora hex=0xabcd", s);
}

test "console: format exact buffer capacity without truncation" {
    var buf: [16]u8 = undefined;
    const msg = "0123456789abcdef";
    const s = format(&buf, "{s}", .{msg});

    try testing.expectEqualStrings(msg, s);
}

test "console: format overflow truncates safely without leaking uninitialized bytes" {
    var buf: [16]u8 = @splat(0xaa);
    const s = format(&buf, "{s}", .{"0123456789abcdef_overflow"});

    try testing.expectEqual(16, s.len);
    try testing.expectEqualStrings("0123456789ab...\n", s);
}

test "console: format overflow mid-token does not return uninitialized tail" {
    var buf: [10]u8 = @splat(0xff);
    // "hello " is 6 bytes, then 12345678 (8 bytes) overflows the 10-byte buffer.
    const s = format(&buf, "hello {d}", .{12345678});

    try testing.expectEqualStrings("hello ...\n", s);
}

test "console: format into empty or tiny buffer" {
    var empty: [0]u8 = .{};

    try testing.expectEqualStrings("", format(&empty, "abc", .{}));

    var tiny: [2]u8 = @splat(0xff);

    try testing.expectEqualStrings("ab", format(&tiny, "abcdef", .{}));
}
