//! Provides a seeded PRNG, and a virtual clock for reproducible runs.
//! Time advances only through explicit calls to advance fn.

const std = @import("std");
const console = @import("console.zig");

pub const name = "detsim";
pub const requires = [_][]const u8{"console"};

pub const seed: u64 = 0x4b6f_7262_6f72_61;

var prng: std.Random.DefaultPrng = .init(seed);
var now_ns: u64 = 0;

/// Return the module's random generator.
pub fn random() std.Random {
    return prng.random();
}

/// Advance the virtual clock by ns nanoseconds.
// TODO: Potential overflow, must be checked.
pub fn advance(ns: u64) void {
    now_ns += ns;
}

/// Return the current virtual time in nanoseconds.
pub fn now() u64 {
    return now_ns;
}

/// Reset sim state and log a reproducible startup value.
pub fn init() !void {
    prng = .init(seed);
    now_ns = 0;

    console.print("detsim: seed=0x{x} first={x}\n", .{ seed, prng.random().int(u32) });

    prng = .init(seed);
}
