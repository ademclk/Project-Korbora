//! Declares a static table of workloads.
//! This module validates and reports the layout; it does not enforce isolation yet.

const console = @import("console.zig");

pub const name = "partition";
pub const requires = [_][]const u8{"console"};

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

// TODO: 
//      - Enforce memory isolation with per-partition address spaces
//      - Enforce each partition's CPU budget and schedule at runtime.
//      - Validate that partition memory regions fit in available RAM
//      and do not overlap when concrete regions are assigned.
comptime {
    var total: u32 = 0;

    for (table) |p| total += p.slice_us;

    // test_control + test_telemetry sum up to 1000us we checking that here
    if (total != 1000) @compileError("partition slices must sum to the 1000us major frame");
}

/// Log the configured partition layout.
pub fn init() !void {
    for (table) |p| {
        console.print("partition: {s} crit={s} mem={d}KiB slice={d}us\n", .{ p.name, @tagName(p.criticality), p.mem_kib, p.slice_us });
    }
}
