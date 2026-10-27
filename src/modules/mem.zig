//! Provides a bump allocator over the heap region defined by linker script.
//! Call lock() after initialization to prevent further allocations.

const std = @import("std");
const console = @import("console.zig");

pub const name = "mem";
pub const requires = [_][]const u8{"console"};

// These are defined by the linker script
extern const __heap_start: u8;
extern const __heap_end: u8;

var cursor: usize = 0;
var end: usize = 0;
var locked: bool = false;

/// Initialize the allocator from the heap bounds defined by linker script.
pub fn init() !void {
    cursor = @intFromPtr(&__heap_start);
    end = @intFromPtr(&__heap_end);

    console.print("mem: {d} KiB free\n", .{(end - cursor) / 1024});
}

/// Prevent all future allocations.
pub fn lock() void {
    locked = true;
}

/// Allocate space for n values of T.
/// Returned memory is uninitialized.
/// TODO: This could cause oversized allocation. Must check for overflows.
pub fn alloc(comptime T: type, n: usize) []T {
    if (locked) @panic("allocation after lock");

    const a: usize = @alignOf(T);
    const start = std.mem.alignForward(usize, cursor, a);
    const bytes = @sizeOf(T) * n;

    if (start + bytes > end) @panic("out of static memory");

    cursor = start + bytes;
    const p: [*]T = @ptrFromInt(start);

    return p[0..n];
}
