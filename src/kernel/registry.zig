//! Comptime module registry.
//!
//! A module is declared:
//!   pub const name: []const u8;
//!   pub const requires: []const []const u8;   // optional if another module is required
//!   pub fn init() anyerror!void;
//!
//! resolve checks the enabled set at compile time and returns it in
//! dependency order. Invalid configs will fail to compile.
const std = @import("std");

/// Return module's dependencies, empty list if it has none.
fn requiresOf(comptime M: type) []const []const u8 {
    if (!@hasDecl(M, "requires")) return &.{};

    const r: []const []const u8 = &M.requires;

    return r;
}

/// Find a module by it's name in the registery.
fn find(comptime all: []const type, comptime name: []const u8) ?usize {
    for (all, 0..) |M, i| {
        if (std.mem.eql(u8, M.name, name)) return i;
    }

    return null;
}

/// Validate the enabled modules and return them in dependency order.
pub fn resolve(comptime all: []const type, comptime enabled: []const []const u8) [enabled.len]type {
    comptime {
        var out: [enabled.len]type = undefined;
        var placed: [enabled.len]bool = @splat(false);
        var idx: [enabled.len]usize = undefined;

        // Resolve module names and reject if duplicates exists.
        for (enabled, 0..) |n, i| {
            idx[i] = find(all, n) orelse @compileError("unknown module: " ++ n);

            for (enabled[0..i]) |m| {
                if (std.mem.eql(u8, m, n)) @compileError("already enabled module: " ++ n);
            }
        }

        // Add modules that their dependencies are already registered.
        var count: usize = 0;
        while (count < enabled.len) {
            const before = count;

            for (enabled, 0..) |n, i| {
                if (placed[i]) continue;

                const M = all[idx[i]];
                var ready = true;

                for (requiresOf(M)) |dep| {
                    var ok = false;

                    for (enabled, 0..) |m, j| {
                        if (placed[j] and std.mem.eql(u8, m, dep)) ok = true;
                    }

                    if (!ok) ready = false;
                }

                if (ready) {
                    placed[i] = true;
                    out[count] = M;
                    count += 1;
                    _ = n;
                }
            }
            
            // Missing dependency or dependency graph has a cycle.
            if (count == before) {
                for (enabled, 0..) |n, i| {
                    if (placed[i]) continue;

                    for (requiresOf(all[idx[i]])) |dep| {
                        if (find(all, dep) == null or !contains(enabled, dep))
                            @compileError("module '" ++ n ++ "' requires '" ++ dep ++ "' which is not enabled");
                    }
                }

                @compileError("module dependency cycle");
            }
        }

        return out;
    }
}

/// Check whether a module name appears in a comptime list.
fn contains(comptime list: []const []const u8, comptime name: []const u8) bool {
    for (list) |n| if (std.mem.eql(u8, n, name)) return true;

    return false;
}

/// Run every module's init in resolved order.
pub fn initAll(comptime order: []const type) !void {
    inline for (order) |M| try M.init();
}

const testing = std.testing;

const T = struct {
    var log: [4]u8 = undefined;
    var n: usize = 0;

    fn mk(comptime nm: []const u8, comptime req: []const []const u8, comptime tag: u8) type {
        return struct {
            pub const name = nm;
            pub const requires: [req.len][]const u8 = req[0..req.len].*;

            pub fn init() !void {
                log[n] = tag;
                n += 1;
            }
        };
    }
};

test "resolves dependency order" {
    const A = T.mk("a", &.{}, 'a');
    const B = T.mk("b", &.{"a"}, 'b');
    const C = T.mk("c", &.{"b"}, 'c');
    const order = comptime resolve(&.{ A, B, C }, &.{ "c", "b", "a" });

    try initAll(&order);
    try testing.expectEqualStrings("abc", T.log[0..3]);
}
