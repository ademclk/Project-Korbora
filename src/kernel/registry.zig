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

pub const max_modules = 256;

pub const ResolveError = error{
    UnknownModule,
    DuplicateModule,
    MissingDependency,
    DependencyCycle,
    DuplicateCatalogueModule,
};

/// Return module's dependencies, empty list if it has none.
fn requiresOf(comptime M: type) []const []const u8 {
    if (!@hasDecl(M, "requires")) return &.{};
    return switch (@typeInfo(@TypeOf(M.requires))) {
        .pointer => M.requires,
        .array => &M.requires,
        else => @compileError("module '" ++ M.name ++ "' has invalid 'requires' type"),
    };
}

/// Find a module by its name in the catalogue.
fn find(comptime all: []const type, comptime name: []const u8) ?usize {
    for (all, 0..) |M, i| {
        if (std.mem.eql(u8, M.name, name)) return i;
    }

    return null;
}

/// Check whether a module name appears in a list.
fn contains(list: []const []const u8, name: []const u8) bool {
    for (list) |n| if (std.mem.eql(u8, n, name)) return true;

    return false;
}

/// Find module name index in a slice of names.
fn findName(all_names: []const []const u8, name: []const u8) ?usize {
    for (all_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) return i;
    }

    return null;
}

/// Count the number of tokens in a comma-separated list of modules.
pub fn countCsv(comptime csv: []const u8) usize {
    return comptime blk: {
        const trimmed = std.mem.trim(u8, csv, " \t\r\n");

        if (trimmed.len == 0) break :blk 0;

        var it = std.mem.splitScalar(u8, trimmed, ',');
        var c: usize = 0;

        while (it.next()) |token| {
            const item = std.mem.trim(u8, token, " \t\r\n");

            if (item.len == 0) {
                @compileError("empty module name in module list");
            }

            c += 1;
        }

        break :blk c;
    };
}

/// Parse a comma-separated list of module names into an array.
pub fn parseCsv(comptime csv: []const u8) [countCsv(csv)][]const u8 {
    return comptime blk: {
        const n = countCsv(csv);

        if (n == 0) break :blk [0][]const u8{};

        const trimmed = std.mem.trim(u8, csv, " \t\r\n");
        var out: [n][]const u8 = undefined;
        var it = std.mem.splitScalar(u8, trimmed, ',');
        var i: usize = 0;

        while (it.next()) |token| : (i += 1) {
            const item = std.mem.trim(u8, token, " \t\r\n");

            if (item.len == 0) {
                @compileError("empty module name in module list");
            }

            out[i] = item;
        }

        break :blk out;
    };
}

/// Runtime/comptime validation of catalogue names, dependencies, and enabled modules.
pub fn validateConfig(
    all_names: []const []const u8,
    all_reqs: []const []const []const u8,
    enabled: []const []const u8,
) ResolveError!void {
    if (enabled.len > max_modules or all_names.len > max_modules) {
        @panic("too many modules");
    }

    // Check duplicate catalogue modules
    for (all_names, 0..) |n, i| {
        for (all_names[0..i]) |m| {
            if (std.mem.eql(u8, m, n)) return error.DuplicateCatalogueModule;
        }
    }

    var idx: [max_modules]usize = undefined;

    // Resolve module names and reject duplicates
    for (enabled, 0..) |n, i| {
        idx[i] = findName(all_names, n) orelse return error.UnknownModule;

        for (enabled[0..i]) |m| {
            if (std.mem.eql(u8, m, n)) return error.DuplicateModule;
        }
    }

    var placed: [max_modules]bool = @splat(false);
    var count: usize = 0;

    while (count < enabled.len) {
        const before = count;

        for (enabled, 0..) |_, i| {
            if (placed[i]) continue;

            const reqs = all_reqs[idx[i]];
            var ready = true;

            for (reqs) |dep| {
                var ok = false;

                for (enabled, 0..) |m, j| {
                    if (placed[j] and std.mem.eql(u8, m, dep)) {
                        ok = true;
                        break;
                    }
                }

                if (!ok) {
                    ready = false;
                    break;
                }
            }

            if (ready) {
                placed[i] = true;
                count += 1;
            }
        }

        if (count == before) {
            // Missing dependency or dependency graph has a cycle.
            for (enabled, 0..) |_, i| {
                if (placed[i]) continue;

                for (all_reqs[idx[i]]) |dep| {
                    if (findName(all_names, dep) == null or !contains(enabled, dep)) {
                        return error.MissingDependency;
                    }
                }
            }

            return error.DependencyCycle;
        }
    }
}

/// Convenience checker for module types and enabled slice.
pub fn check(comptime all: []const type, enabled: []const []const u8) ResolveError!void {
    const names = comptime blk: {
        var n: [all.len][]const u8 = undefined;

        for (all, 0..) |M, i| n[i] = M.name;

        break :blk n;
    };

    const reqs = comptime blk: {
        var r: [all.len][]const []const u8 = undefined;

        for (all, 0..) |M, i| r[i] = requiresOf(M);

        break :blk r;
    };

    return validateConfig(&names, &reqs, enabled);
}

/// Validate the enabled modules and return them in dependency order.
pub fn resolve(comptime all: []const type, comptime enabled: []const []const u8) [enabled.len]type {
    comptime {
        var out: [enabled.len]type = undefined;
        var placed: [enabled.len]bool = @splat(false);
        var idx: [enabled.len]usize = undefined;

        // Check catalogue duplicates
        for (all, 0..) |M, i| {
            for (all[0..i]) |N| {
                if (std.mem.eql(u8, M.name, N.name))
                    @compileError("duplicate module in catalogue: " ++ M.name);
            }
        }

        // Resolve module names and reject if duplicates exist.
        for (enabled, 0..) |n, i| {
            idx[i] = find(all, n) orelse @compileError("unknown module: " ++ n);

            for (enabled[0..i]) |m| {
                if (std.mem.eql(u8, m, n)) @compileError("already enabled module: " ++ n);
            }
        }

        // Add modules whose dependencies are already registered.
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

/// Run every module's init in resolved order.
pub fn initAll(comptime order: []const type) !void {
    inline for (order) |M| try M.init();
}

const testing = std.testing;

const T = struct {
    var log: [16]u8 = undefined;
    var n: usize = 0;

    fn reset() void {
        n = 0;
    }

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

    fn mkFail(comptime nm: []const u8, comptime req: []const []const u8, comptime tag: u8) type {
        return struct {
            pub const name = nm;
            pub const requires: [req.len][]const u8 = req[0..req.len].*;

            pub fn init() !void {
                log[n] = tag;
                n += 1;
                return error.InitFailed;
            }
        };
    }
};

test "linear dependency chain" {
    T.reset();
    const A = T.mk("a", &.{}, 'a');
    const B = T.mk("b", &.{"a"}, 'b');
    const C = T.mk("c", &.{"b"}, 'c');
    const order = comptime resolve(&.{ A, B, C }, &.{ "c", "b", "a" });

    try initAll(&order);
    try testing.expectEqualStrings("abc", T.log[0..T.n]);
}

test "diamond dependency graph" {
    T.reset();
    const A = T.mk("a", &.{}, 'a');
    const B = T.mk("b", &.{"a"}, 'b');
    const C = T.mk("c", &.{"a"}, 'c');
    const D = T.mk("d", &.{ "b", "c" }, 'd');
    const order = comptime resolve(&.{ A, B, C, D }, &.{ "d", "c", "b", "a" });

    try initAll(&order);
    try testing.expectEqual(4, T.n);
    try testing.expectEqual('a', T.log[0]);
    try testing.expect((T.log[1] == 'b' and T.log[2] == 'c') or (T.log[1] == 'c' and T.log[2] == 'b'));
    try testing.expectEqual('d', T.log[3]);
}

test "empty enabled module list" {
    T.reset();
    const A = T.mk("a", &.{}, 'a');
    const order = comptime resolve(&.{A}, &.{});

    try initAll(&order);
    try testing.expectEqual(0, T.n);
    try check(&.{A}, &.{});
}

test "requires declaration variants" {
    T.reset();

    const NoReq = struct {
        pub const name = "noreq";
        pub fn init() !void {
            T.log[T.n] = '1';
            T.n += 1;
        }
    };
    const ArrayReq = struct {
        pub const name = "array";
        pub const requires: [1][]const u8 = .{"noreq"};
        pub fn init() !void {
            T.log[T.n] = '2';
            T.n += 1;
        }
    };
    const SliceReq = struct {
        pub const name = "slice";
        pub const requires: []const []const u8 = &.{"array"};
        pub fn init() !void {
            T.log[T.n] = '3';
            T.n += 1;
        }
    };

    const order = comptime resolve(&.{ NoReq, ArrayReq, SliceReq }, &.{ "slice", "noreq", "array" });

    try initAll(&order);
    try testing.expectEqualStrings("123", T.log[0..T.n]);
}

test "check error unknown module" {
    const A = T.mk("a", &.{}, 'a');

    try testing.expectError(error.UnknownModule, check(&.{A}, &.{"nonexistent"}));
}

test "check error duplicate module" {
    const A = T.mk("a", &.{}, 'a');

    try testing.expectError(error.DuplicateModule, check(&.{A}, &.{ "a", "a" }));
}

test "check error missing dependency" {
    const A = T.mk("a", &.{}, 'a');
    const B = T.mk("b", &.{"a"}, 'b');

    // dep "a" exists in all, not enabled
    try testing.expectError(error.MissingDependency, check(&.{ A, B }, &.{"b"}));

    // dep "ghost" does not exist in all
    const C = T.mk("c", &.{"ghost"}, 'c');

    try testing.expectError(error.MissingDependency, check(&.{ A, C }, &.{"c"}));
}

test "check error dependency cycle" {
    // Self-dependency a -> a
    const SelfCycle = T.mk("a", &.{"a"}, 'a');

    try testing.expectError(error.DependencyCycle, check(&.{SelfCycle}, &.{"a"}));

    // 2-node cycle a <-> b
    const Cyc2A = T.mk("a", &.{"b"}, 'a');
    const Cyc2B = T.mk("b", &.{"a"}, 'b');

    try testing.expectError(error.DependencyCycle, check(&.{ Cyc2A, Cyc2B }, &.{ "a", "b" }));

    // 3-node cycle a -> b -> c -> a
    const Cyc3A = T.mk("a", &.{"b"}, 'a');
    const Cyc3B = T.mk("b", &.{"c"}, 'b');
    const Cyc3C = T.mk("c", &.{"a"}, 'c');

    try testing.expectError(error.DependencyCycle, check(&.{ Cyc3A, Cyc3B, Cyc3C }, &.{ "a", "b", "c" }));

    // Cycle with an independent valid module base, a <-> b
    const Base = T.mk("base", &.{}, '0');

    try testing.expectError(error.DependencyCycle, check(&.{ Base, Cyc2A, Cyc2B }, &.{ "base", "a", "b" }));
}

test "check error duplicate catalogue module" {
    const A1 = T.mk("dup", &.{}, '1');
    const A2 = T.mk("dup", &.{}, '2');

    try testing.expectError(error.DuplicateCatalogueModule, check(&.{ A1, A2 }, &.{"dup"}));
}

test "initAll error propagation" {
    T.reset();
    const A = T.mk("a", &.{}, 'a');
    const BFail = T.mkFail("b", &.{"a"}, 'b');
    const C = T.mk("c", &.{"b"}, 'c');

    const order = comptime resolve(&.{ A, BFail, C }, &.{ "a", "b", "c" });

    try testing.expectError(error.InitFailed, initAll(&order));
    try testing.expectEqualStrings("ab", T.log[0..T.n]);
}

test "parseCsv variants" {
    const empty = parseCsv("");

    try testing.expectEqual(0, empty.len);

    const single = parseCsv("console");

    try testing.expectEqual(1, single.len);
    try testing.expectEqualStrings("console", single[0]);

    const multiple = parseCsv("console,mem");

    try testing.expectEqual(2, multiple.len);
    try testing.expectEqualStrings("console", multiple[0]);
    try testing.expectEqualStrings("mem", multiple[1]);

    const spaced = parseCsv(" console , mem , detsim ");

    try testing.expectEqual(3, spaced.len);
    try testing.expectEqualStrings("console", spaced[0]);
    try testing.expectEqualStrings("mem", spaced[1]);
    try testing.expectEqualStrings("detsim", spaced[2]);
}

test "validateConfig direct" {
    const names = [_][]const u8{ "a", "b" };
    const reqs_a: []const []const u8 = &.{};
    const reqs_b: []const []const u8 = &.{"a"};
    const all_reqs = [_][]const []const u8{ reqs_a, reqs_b };

    try validateConfig(&names, &all_reqs, &.{ "b", "a" });
    try testing.expectError(error.UnknownModule, validateConfig(&names, &all_reqs, &.{"c"}));
}
