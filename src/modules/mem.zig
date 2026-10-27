//! Provides a bump allocator over the heap region defined by linker script.
//! Call lock() after initialization to prevent further allocations.

const std = @import("std");
const console = @import("console.zig");

pub const name = "mem";
pub const requires = [_][]const u8{"console"};

pub const Error = error{
    Locked,
    OutOfMemory,
    Uninitialized,
    InvalidBounds,
};

// These are defined by the linker script
extern const __heap_start: u8;
extern const __heap_end: u8;

var cursor: usize = 0;
var end: usize = 0;
var locked: bool = false;

/// Initialize the allocator from the heap bounds defined by linker script.
pub fn init() !void {
    try initRegion(@intFromPtr(&__heap_start), @intFromPtr(&__heap_end));

    console.print("mem: {d} KiB free\n", .{(end - cursor) / 1024});
}

/// Initialize the allocator with explicit memory region bounds.
pub fn initRegion(start_addr: usize, end_addr: usize) Error!void {
    if (start_addr == 0 or end_addr < start_addr) return error.InvalidBounds;

    cursor = start_addr;
    end = end_addr;
    locked = false;
}

/// Check whether the allocator has been locked.
pub fn isLocked() bool {
    return locked;
}

/// Return number of free bytes remaining in the region.
pub fn freeBytes() usize {
    return if (end >= cursor) end - cursor else 0;
}

/// Prevent all future allocations.
pub fn lock() void {
    locked = true;
}

/// Attempt to allocate space for n values of T with checked arithmetic.
pub fn tryAlloc(comptime T: type, n: usize) Error![]T {
    if (locked) return error.Locked;
    if (cursor == 0 or end == 0 or end < cursor) return error.Uninitialized;

    const a: usize = @alignOf(T);
    const aligned_tmp = std.math.add(usize, cursor, a - 1) catch return error.OutOfMemory;
    const start = aligned_tmp & ~(a - 1);

    const bytes = std.math.mul(usize, @sizeOf(T), n) catch return error.OutOfMemory;

    const next = std.math.add(usize, start, bytes) catch return error.OutOfMemory;
    if (next > end) return error.OutOfMemory;

    cursor = next;
    const p: [*]T = @ptrFromInt(start);

    return p[0..n];
}

/// Allocate space for n values of T.
/// Returned memory is uninitialized.
pub fn alloc(comptime T: type, n: usize) []T {
    return tryAlloc(T, n) catch |err| switch (err) {
        error.Locked => @panic("allocation after lock"),
        error.Uninitialized, error.InvalidBounds => @panic("allocator not initialized"),
        error.OutOfMemory => @panic("out of static memory"),
    };
}

test "mem: initRegion initializes bounds and unlocks allocator" {
    var buf: [4096]u8 align(64) = undefined;
    const base = @intFromPtr(&buf[0]);

    try initRegion(base, base + buf.len);
    try std.testing.expect(!isLocked());
    try std.testing.expectEqual(buf.len, freeBytes());
}

test "mem: initRegion rejects invalid bounds" {
    try std.testing.expectError(error.InvalidBounds, initRegion(0, 100));
    try std.testing.expectError(error.InvalidBounds, initRegion(100, 50));
}

test "mem: tryAlloc before initialization returns Uninitialized" {
    cursor = 0;
    end = 0;
    locked = false;

    try std.testing.expectError(error.Uninitialized, tryAlloc(u8, 1));
    try std.testing.expectError(error.Uninitialized, tryAlloc(u8, 0));
}

test "mem: basic allocation and freeBytes tracking" {
    var buf: [1024]u8 align(64) = undefined;
    const base = @intFromPtr(&buf[0]);
    try initRegion(base, base + buf.len);

    const initial_free = freeBytes();
    const slice = alloc(u32, 4);
    try std.testing.expectEqual(4, slice.len);

    for (slice, 0..) |*item, idx| {
        item.* = @intCast(idx * 10);
    }
    for (slice, 0..) |item, idx| {
        try std.testing.expectEqual(@as(u32, @intCast(idx * 10)), item);
    }
    try std.testing.expect(freeBytes() <= initial_free - (4 * @sizeOf(u32)));
}

test "mem: alignment enforcement across mixed types" {
    var buf: [1024]u8 align(64) = undefined;
    const base = @intFromPtr(&buf[0]);
    try initRegion(base, base + buf.len);

    const Aligned64 = struct { x: u8 align(64) };

    const s_u8 = alloc(u8, 3);
    try std.testing.expectEqual(0, @intFromPtr(s_u8.ptr) % @alignOf(u8));

    const s_u16 = alloc(u16, 3);
    try std.testing.expectEqual(0, @intFromPtr(s_u16.ptr) % @alignOf(u16));

    const s_u32 = alloc(u32, 3);
    try std.testing.expectEqual(0, @intFromPtr(s_u32.ptr) % @alignOf(u32));

    const s_u64 = alloc(u64, 3);
    try std.testing.expectEqual(0, @intFromPtr(s_u64.ptr) % @alignOf(u64));

    const s_u128 = alloc(u128, 3);
    try std.testing.expectEqual(0, @intFromPtr(s_u128.ptr) % @alignOf(u128));

    const s_a64 = alloc(Aligned64, 2);
    try std.testing.expectEqual(0, @intFromPtr(s_a64.ptr) % 64);
}

test "mem: zero count and zero sized allocations" {
    var buf: [256]u8 align(16) = undefined;
    const base = @intFromPtr(&buf[0]);
    try initRegion(base, base + buf.len);

    const s0 = alloc(u64, 0);
    try std.testing.expectEqual(0, s0.len);

    const zst = alloc(u0, 100);
    try std.testing.expectEqual(100, zst.len);
}

test "mem: exact boundary allocation" {
    var buf: [128]u8 align(16) = undefined;
    const base = @intFromPtr(&buf[0]);
    try initRegion(base, base + buf.len);

    const remaining = freeBytes();
    const slice = alloc(u8, remaining);
    try std.testing.expectEqual(remaining, slice.len);
    try std.testing.expectEqual(0, freeBytes());
    try std.testing.expectError(error.OutOfMemory, tryAlloc(u8, 1));
}

test "mem: multiplication overflow returns OutOfMemory without modifying cursor" {
    var buf: [128]u8 align(16) = undefined;
    const base = @intFromPtr(&buf[0]);
    try initRegion(base, base + buf.len);

    const cur_before = cursor;
    const overflow_count = (std.math.maxInt(usize) / 8) + 1;
    try std.testing.expectError(error.OutOfMemory, tryAlloc(u64, overflow_count));
    try std.testing.expectEqual(cur_before, cursor);
}

test "mem: addition overflow returns OutOfMemory" {
    cursor = std.math.maxInt(usize) - 100;
    end = std.math.maxInt(usize);
    locked = false;
    try std.testing.expectError(error.OutOfMemory, tryAlloc(u8, 200));
}

test "mem: alignment overflow returns OutOfMemory" {
    cursor = std.math.maxInt(usize) - 10;
    end = std.math.maxInt(usize);
    locked = false;
    const Aligned64 = struct { x: u8 align(64) };
    try std.testing.expectError(error.OutOfMemory, tryAlloc(Aligned64, 1));
}

test "mem: lock prevents subsequent allocations" {
    var buf: [128]u8 align(16) = undefined;
    const base = @intFromPtr(&buf[0]);
    try initRegion(base, base + buf.len);

    try std.testing.expect(!isLocked());
    lock();
    try std.testing.expect(isLocked());
    try std.testing.expectError(error.Locked, tryAlloc(u8, 1));
    try std.testing.expectError(error.Locked, tryAlloc(u8, 0));
}
