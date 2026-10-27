//! Catalogue of every module that can be linked into an image.
//! Only modules named in the image configuration are analyzed and compiled.

pub const list = [_]type{
    @import("console.zig"),
    @import("mem.zig"),
    @import("measure.zig"),
    @import("partition.zig"),
    @import("detsim.zig"),
};
