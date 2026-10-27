//! Kernel entry. The set of modules is chosen at build time (using -Dmodules=).

const std = @import("std");
const config = @import("config");
const registry = @import("kernel/registry.zig");
const all = @import("modules/all.zig");
const builtin = @import("builtin");
const uart = @import("arch/aarch64/uart.zig");

comptime {
    _ = @import("arch/aarch64/boot.zig");
}

const enabled = registry.parseCsv(config.modules);
const order = registry.resolve(&all.list, &enabled);

export fn kmain() noreturn {
    registry.initAll(&order) catch @panic("module init failed");

    inline for (order) |M| {
        if (comptime std.mem.eql(u8, M.name, "mem")) {
            M.lock();
        }
    }

    while (true) asm volatile ("wfe");
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    if (builtin.cpu.arch == .aarch64) asm volatile ("msr daifset, #0xf");

    uart.write("\nPANIC: ");
    uart.write(msg);
    uart.write("\n");

    while (true) asm volatile ("wfe");
}
