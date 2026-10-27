//! Host-testable pieces of Korbora.

const std = @import("std");
const registry = @import("kernel/registry.zig");
const all = @import("modules/all.zig");

test {
    _ = @import("kernel/registry.zig");
    _ = @import("modules/all.zig");
    _ = @import("modules/console.zig");
    _ = @import("modules/mem.zig");
    _ = @import("modules/measure.zig");
    _ = @import("modules/partition.zig");
    _ = @import("modules/detsim.zig");
}

test "integration: resolve default module catalogue dependency order" {
    const enabled = comptime registry.parseCsv("detsim,partition,measure,mem,console");
    const order = comptime registry.resolve(&all.list, &enabled);

    try std.testing.expectEqual(5, order.len);
    // console has no dependencies and is required by all other default modules,
    // so it must always be resolved first.
    try std.testing.expectEqualStrings("console", order[0].name);
}
