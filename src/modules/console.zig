//! Console is used for serial output and formatted printing.

const std = @import("std");
const uart = @import("../arch/aarch64/uart.zig");

pub const name = "console";

pub fn init() !void {
    uart.write("Hello from Korbora\n");
}

// TODO: formatting failure should be handled.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const s = std.mem.print(&buf, fmt, args) catch buf[0..];

    uart.write(s);
}

pub fn write(s: []const u8) void {
    uart.write(s);
}
