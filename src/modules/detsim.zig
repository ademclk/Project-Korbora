//! Provides a seeded PRNG, and a virtual clock for reproducible runs.
//! Time advances only through explicit calls to advance fn.

const std = @import("std");
const console = @import("console.zig");

pub const name = "detsim";
pub const requires = [_][]const u8{"console"};

pub const seed: u64 = 0x4b6f_7262_6f72_61;

pub const Error = error{Overflow};

var prng: std.Random.DefaultPrng = .init(seed);
var now_ns: u64 = 0;

/// Return the module's random generator.
pub fn random() std.Random {
    return prng.random();
}

/// Reset generator to custom seed and reset virtual clock to 0.
pub fn reset(custom_seed: u64) void {
    prng = .init(custom_seed);
    now_ns = 0;
}

/// Advance the virtual clock by ns nanoseconds with overflow checking.
pub fn tryAdvance(ns: u64) Error!void {
    now_ns = std.math.add(u64, now_ns, ns) catch return error.Overflow;
}

/// Advance the virtual clock by ns nanoseconds.
pub fn advance(ns: u64) void {
    tryAdvance(ns) catch @panic("virtual clock overflow");
}

/// Return the current virtual time in nanoseconds.
pub fn now() u64 {
    return now_ns;
}

/// Reset sim state and log a reproducible startup value.
pub fn init() !void {
    reset(seed);

    console.print("detsim: seed=0x{x} first={x}\n", .{ seed, prng.random().int(u32) });

    prng = .init(seed);
}

test "detsim: reset sets clock to 0 and PRNG to reproducible first value" {
    reset(seed);

    try std.testing.expectEqual(@as(u64, 0), now());

    const val = random().int(u32);

    try std.testing.expectEqual(@as(u32, 0xaa352406), val);
}

test "detsim: determinism across multiple reset calls" {
    reset(seed);
    var seq1: [5]u32 = undefined;
    for (&seq1) |*v| v.* = random().int(u32);

    reset(seed);
    var seq2: [5]u32 = undefined;
    for (&seq2) |*v| v.* = random().int(u32);

    try std.testing.expectEqualSlices(u32, &seq1, &seq2);

    reset(0x1234_5678_9abc_def0);
    var custom1: [5]u64 = undefined;
    for (&custom1) |*v| v.* = random().int(u64);

    reset(0x1234_5678_9abc_def0);
    var custom2: [5]u64 = undefined;
    for (&custom2) |*v| v.* = random().int(u64);

    try std.testing.expectEqualSlices(u64, &custom1, &custom2);
}

test "detsim: advance and now progression" {
    reset(seed);

    try std.testing.expectEqual(@as(u64, 0), now());

    advance(0);
    try std.testing.expectEqual(@as(u64, 0), now());

    advance(100);
    try std.testing.expectEqual(@as(u64, 100), now());

    advance(250);
    try std.testing.expectEqual(@as(u64, 350), now());
}

test "detsim: tryAdvance overflow detection preserves now_ns" {
    reset(seed);
    advance(std.math.maxInt(u64) - 50);
    const before = now();

    try std.testing.expectError(error.Overflow, tryAdvance(51));
    try std.testing.expectEqual(before, now());
    try std.testing.expectError(error.Overflow, tryAdvance(std.math.maxInt(u64)));
    try std.testing.expectEqual(before, now());
    try tryAdvance(50);
    try std.testing.expectEqual(std.math.maxInt(u64), now());
}
