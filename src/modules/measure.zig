//! Computes a SHA-256 digest of the image range marked by the linker.
//! A verifier can compare this digest with an expected value from a manifest.

const std = @import("std");
const console = @import("console.zig");

pub const name = "measure";
pub const requires = [_][]const u8{"console"};

// These are defined by the linker script
extern const __image_start: u8;
extern const __image_end: u8;

// SHA 256 digest of the image
pub var digest: [32]u8 = @splat(0);

pub fn init() !void {
    const s = @intFromPtr(&__image_start);
    const e = @intFromPtr(&__image_end);
    const image: [*]const u8 = @ptrCast(&__image_start);

    std.crypto.hash.sha2.Sha256.hash(image[0 .. e - s], &digest, .{});
    
    console.print("measure: image {d} bytes sha256={x}\n", .{ e - s, digest });
}
