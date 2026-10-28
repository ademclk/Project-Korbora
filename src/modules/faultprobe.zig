//! Test-only module for the fault-visibility exit check (M2).
//!
//! It enables EL1 alignment checking and performs a deliberately misaligned
//! 64-bit load. The resulting data abort must reach the exception vector
//! table, print the fault report and halt the core. Without the vector table
//! this image would either spin or reset.
//!
//! Build it into an image with:
//!     zig build run -Dmodules=console,faultprobe

const builtin = @import("builtin");
const console = @import("console.zig");

pub const name = "faultprobe";
pub const requires = [_][]const u8{"console"};

pub fn init() !void {
    if (comptime builtin.cpu.arch != .aarch64) return error.UnsupportedArch;

    console.print("faultprobe: triggering a deliberate misaligned data access\n", .{});
    triggerBadAccess();
}

/// Perform a misaligned data access with SCTLR_EL1.A set.
/// The access faults on the first instruction, so this function never returns
/// on a working vector table.
pub fn triggerBadAccess() void {
    const buf: [16]u8 align(8) = @splat(0xaa);

    // Enable alignment checking for EL1 data accesses. This is independent of
    // the MMU, so the probe works before paging is introduced in M4.
    var sctlr: u64 = undefined;
    asm volatile ("mrs %[value], sctlr_el1"
        : [value] "=r" (sctlr),
    );
    sctlr |= @as(u64, 1) << 1;
    asm volatile ("msr sctlr_el1, %[value]"
        :
        : [value] "r" (sctlr),
        : .{ .memory = true });
    asm volatile ("isb");

    // +1 makes the 8-byte load misaligned. The address is still inside the
    // stack buffer, so only the alignment check can fault it.
    const addr = @intFromPtr(&buf[0]) + 1;
    asm volatile ("ldr x0, [%[addr]]"
        :
        : [addr] "r" (addr),
        : .{ .x0 = true, .memory = true });

    @panic("faultprobe: misaligned access did not fault");
}
