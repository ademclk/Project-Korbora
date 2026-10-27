//! Declares a static table of workloads.
//! This module validates and reports the layout; it does not enforce isolation yet.

const std = @import("std");
const console = @import("console.zig");

pub const name = "partition";
pub const requires = [_][]const u8{"console"};

pub const major_frame_us: u32 = 1000;
pub const max_total_mem_kib: u32 = 126 * 1024;

pub const Partition = struct {
    name: []const u8,
    criticality: enum { high, low },
    mem_kib: u32,
    slice_us: u32,
};

// test partitions
pub const table = [_]Partition{
    .{ .name = "test_control", .criticality = .high, .mem_kib = 1024, .slice_us = 800 },
    .{ .name = "test_telemetry", .criticality = .low, .mem_kib = 4096, .slice_us = 200 },
};

pub const ValidationError = error{
    EmptyTable,
    EmptyName,
    DuplicateName,
    ZeroSlice,
    ZeroMemory,
    SliceOverflow,
    InvalidFrameSum,
    MemoryOverflow,
    ExceedsMemoryBudget,
};

pub fn validate(partitions: []const Partition) ValidationError!void {
    if (partitions.len == 0) return error.EmptyTable;

    var total_slice: u32 = 0;
    var total_mem: u32 = 0;

    for (partitions, 0..) |p, i| {
        if (p.name.len == 0) return error.EmptyName;
        for (partitions[0..i]) |prev| {
            if (std.mem.eql(u8, prev.name, p.name)) return error.DuplicateName;
        }
        if (p.slice_us == 0) return error.ZeroSlice;
        if (p.mem_kib == 0) return error.ZeroMemory;

        total_slice = std.math.add(u32, total_slice, p.slice_us) catch return error.SliceOverflow;
        total_mem = std.math.add(u32, total_mem, p.mem_kib) catch return error.MemoryOverflow;
    }

    if (total_slice != major_frame_us) return error.InvalidFrameSum;
    if (total_mem > max_total_mem_kib) return error.ExceedsMemoryBudget;
}

// Static memory and slice validation is implemented via `validate()`.
// Runtime MMU memory isolation and scheduler enforcement are scheduled for Phase C (M10/M11).
comptime {
    validate(&table) catch |err| switch (err) {
        error.InvalidFrameSum => @compileError("partition slices must sum to the 1000us major frame"),
        error.EmptyTable => @compileError("partition table cannot be empty"),
        error.EmptyName => @compileError("partition name cannot be empty"),
        error.DuplicateName => @compileError("duplicate partition name in partition table"),
        error.ZeroSlice => @compileError("partition time slice cannot be zero"),
        error.ZeroMemory => @compileError("partition memory cannot be zero"),
        error.SliceOverflow => @compileError("partition time slices overflow u32"),
        error.MemoryOverflow => @compileError("partition memory allocations overflow u32"),
        error.ExceedsMemoryBudget => @compileError("partition total memory exceeds available RAM budget"),
    };
}

/// Log the configured partition layout.
pub fn init() !void {
    for (table) |p| {
        console.print("partition: {s} crit={s} mem={d}KiB slice={d}us\n", .{ p.name, @tagName(p.criticality), p.mem_kib, p.slice_us });
    }
}

test "partition: validate table succeeds" {
    try validate(&table);
}

test "partition: validate empty table returns EmptyTable" {
    try std.testing.expectError(error.EmptyTable, validate(&.{}));
}

test "partition: empty partition name returns EmptyName" {
    const invalid = [_]Partition{
        .{ .name = "", .criticality = .high, .mem_kib = 1024, .slice_us = 1000 },
    };
    try std.testing.expectError(error.EmptyName, validate(&invalid));
}

test "partition: duplicate partition name returns DuplicateName" {
    const invalid = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = 1024, .slice_us = 500 },
        .{ .name = "part_a", .criticality = .low, .mem_kib = 1024, .slice_us = 500 },
    };
    try std.testing.expectError(error.DuplicateName, validate(&invalid));
}

test "partition: zero slice returns ZeroSlice" {
    const invalid = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = 1024, .slice_us = 0 },
        .{ .name = "part_b", .criticality = .low, .mem_kib = 1024, .slice_us = 1000 },
    };
    try std.testing.expectError(error.ZeroSlice, validate(&invalid));
}

test "partition: zero memory returns ZeroMemory" {
    const invalid = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = 0, .slice_us = 1000 },
    };
    try std.testing.expectError(error.ZeroMemory, validate(&invalid));
}

test "partition: slice_us sum overflow returns SliceOverflow" {
    const invalid = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = 1024, .slice_us = std.math.maxInt(u32) },
        .{ .name = "part_b", .criticality = .low, .mem_kib = 1024, .slice_us = 1 },
    };
    try std.testing.expectError(error.SliceOverflow, validate(&invalid));
}

test "partition: slice_us sum != 1000 returns InvalidFrameSum" {
    const less = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = 1024, .slice_us = 999 },
    };
    try std.testing.expectError(error.InvalidFrameSum, validate(&less));

    const more = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = 1024, .slice_us = 1001 },
    };
    try std.testing.expectError(error.InvalidFrameSum, validate(&more));
}

test "partition: mem_kib sum overflow returns MemoryOverflow" {
    const invalid = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = std.math.maxInt(u32), .slice_us = 500 },
        .{ .name = "part_b", .criticality = .low, .mem_kib = 1, .slice_us = 500 },
    };
    try std.testing.expectError(error.MemoryOverflow, validate(&invalid));
}

test "partition: mem_kib sum > max_total_mem_kib returns ExceedsMemoryBudget" {
    const invalid = [_]Partition{
        .{ .name = "part_a", .criticality = .high, .mem_kib = max_total_mem_kib + 1, .slice_us = 1000 },
    };
    try std.testing.expectError(error.ExceedsMemoryBudget, validate(&invalid));
}
