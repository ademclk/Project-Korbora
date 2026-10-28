//! Catalogue of every module that can be linked into an image.
//! Only modules named in the image configuration are analyzed and compiled.

const builtin = @import("builtin");

const core = [_]type{
    @import("console.zig"),
    @import("mem.zig"),
    @import("measure.zig"),
    @import("partition.zig"),
    @import("detsim.zig"),
};

// faultprobe contains AArch64-only probe code, so it is not part of the
// catalogue when the host-side unit tests compile this file.
const faultprobe = if (builtin.cpu.arch == .aarch64)
    [_]type{@import("faultprobe.zig")}
else
    [_]type{};

pub const list = core ++ faultprobe;
