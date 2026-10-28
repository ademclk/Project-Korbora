//! Compare a captured QEMU serial log against an expected transcript.
//!
//! Usage: transcript-check <expected-transcript> <actual-serial-log>
//!
//! Exits 0 on a match, 1 on a mismatch and 2 on a usage or I/O error.

const std = @import("std");
const transcript = @import("transcript.zig");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    defer args.deinit();

    _ = args.next();

    const expected_path = args.next() orelse usage();
    const actual_path = args.next() orelse usage();

    if (args.next() != null) usage();

    const dir = std.Io.Dir.cwd();
    const expected = dir.readFileAlloc(init.io, expected_path, init.gpa, .limited(1 << 20)) catch |err| {
        std.debug.print("transcript-check: cannot read '{s}': {t}\n", .{ expected_path, err });
        std.process.exit(2);
    };
    defer init.gpa.free(expected);

    const actual = dir.readFileAlloc(init.io, actual_path, init.gpa, .limited(1 << 20)) catch |err| {
        std.debug.print("transcript-check: cannot read '{s}': {t}\n", .{ actual_path, err });
        std.process.exit(2);
    };
    defer init.gpa.free(actual);

    const mismatch = transcript.compare(expected, actual) orelse return;

    std.debug.print("transcript mismatch at line {d}\n", .{mismatch.line});

    if (mismatch.expected) |line| {
        std.debug.print("  expected: {s}\n", .{line});
    } else {
        std.debug.print("  expected: <end of file>\n", .{});
    }

    if (mismatch.actual) |line| {
        std.debug.print("  actual:   {s}\n", .{line});
    } else {
        std.debug.print("  actual:   <end of file>\n", .{});
    }

    std.process.exit(1);
}

fn usage() noreturn {
    std.debug.print("usage: transcript-check <expected-transcript> <actual-serial-log>\n", .{});
    std.process.exit(2);
}
