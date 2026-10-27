//! Computes a SHA-256 digest of the image range marked by the linker.
//! A verifier can compare this digest with an expected value from a manifest.

const std = @import("std");
const console = @import("console.zig");

pub const name = "measure";
pub const requires = [_][]const u8{"console"};

pub const Error = error{InvalidImageBounds};

// These are defined by the linker script
extern const __image_start: u8;
extern const __image_end: u8;

// SHA 256 digest of the image
pub var digest: [32]u8 = @splat(0);

/// Compute SHA-256 digest of a slice into `digest` and return it.
pub fn measureSlice(bytes: []const u8) [32]u8 {
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});

    return digest;
}

/// Compute SHA-256 digest of a memory range.
pub fn measureRange(start_addr: usize, end_addr: usize) Error![32]u8 {
    if (start_addr == 0 or end_addr < start_addr) return error.InvalidImageBounds;

    const ptr: [*]const u8 = @ptrFromInt(start_addr);
    const slice = ptr[0 .. end_addr - start_addr];

    return measureSlice(slice);
}

pub fn init() !void {
    const s = @intFromPtr(&__image_start);
    const e = @intFromPtr(&__image_end);

    _ = try measureRange(s, e);

    console.print("measure: image {d} bytes sha256={x}\n", .{ e - s, digest });
}

test "measure: measureSlice empty input matches known SHA-256" {
    const expected = [32]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    const result = measureSlice("");

    try std.testing.expectEqualSlices(u8, &expected, &result);
    try std.testing.expectEqualSlices(u8, &expected, &digest);
}

test "measure: measureSlice abc matches NIST SHA-256 vector" {
    const expected = [32]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    const result = measureSlice("abc");

    try std.testing.expectEqualSlices(u8, &expected, &result);
    try std.testing.expectEqualSlices(u8, &expected, &digest);
}

test "measure: measureRange rejects invalid bounds" {
    try std.testing.expectError(error.InvalidImageBounds, measureRange(0, 100));
    try std.testing.expectError(error.InvalidImageBounds, measureRange(100, 50));
}

test "measure: measureRange on valid buffer matches measureSlice" {
    const data = "test payload for measure range verification";
    const start = @intFromPtr(&data[0]);
    const end = start + data.len;
    const r_hash = try measureRange(start, end);
    const s_hash = measureSlice(data);

    try std.testing.expectEqualSlices(u8, &s_hash, &r_hash);
}
