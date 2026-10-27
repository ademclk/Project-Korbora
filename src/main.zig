//! Kernel entry. The set of modules is chosen at build time (using -Dmodules=).

const std = @import("std");
const config = @import("config");
const registry = @import("kernel/registry.zig");
const all = @import("modules/all.zig");

comptime {
    _ = @import("arch/aarch64/boot.zig");
}

const enabled = parse(config.modules);
const order = registry.resolve(&all.list, &enabled);

fn parse(comptime csv: []const u8) [count(csv)][]const u8 {
    comptime {
        var out: [count(csv)][]const u8 = undefined;
        var it = std.mem.splitScalar(u8, csv, ',');
        var i: usize = 0;

        while (it.next()) |n| : (i += 1) out[i] = n;

        return out;
    }
}

fn count(comptime csv: []const u8) usize {
    return std.mem.count(u8, csv, ",") + 1;
}

export fn kmain() noreturn {
    registry.initAll(&order) catch @panic("module init failed");

    inline for (all.list) |M| {
        if (comptime std.mem.eql(u8, M.name, "mem")) {
            if (comptime isEnabled("mem")) M.lock();
        }
    }

    while (true) asm volatile ("wfe");
}

fn isEnabled(comptime n: []const u8) bool {
    inline for (enabled) |e| if (std.mem.eql(u8, e, n)) return true;

    return false;
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    const uart = @import("arch/aarch64/uart.zig");

    uart.write("\nPANIC: ");
    uart.write(msg);
    uart.write("\n");
    
    while (true) asm volatile ("wfe");
}
