//! Line-based comparison of QEMU serial output against an expected transcript.
//!
//! The expected transcript is literal text except for two wildcards:
//!   `*` matches any run of characters (including none)
//!   `?` matches exactly one character
//!
//! Wildcards are intentionally line-scoped so a transcript cannot accidentally
//! swallow a missing or extra line.

const std = @import("std");

pub const Mismatch = struct {
    /// 1-based line number of the first difference.
    line: usize,
    expected: ?[]const u8,
    actual: ?[]const u8,
};

/// Compare two transcripts line by line. Returns null when they match.
pub fn compare(expected: []const u8, actual: []const u8) ?Mismatch {
    var expected_index: usize = 0;
    var actual_index: usize = 0;
    var line: usize = 0;

    while (true) {
        const expected_line = nextLine(expected, &expected_index);
        const actual_line = nextLine(actual, &actual_index);

        if (expected_line == null and actual_line == null) return null;

        line += 1;

        if (expected_line == null or actual_line == null) {
            return .{ .line = line, .expected = expected_line, .actual = actual_line };
        }

        if (!globMatch(expected_line.?, actual_line.?)) {
            return .{ .line = line, .expected = expected_line, .actual = actual_line };
        }
    }
}

/// Return the next line without its trailing `\n` or `\r\n`.
fn nextLine(text: []const u8, index: *usize) ?[]const u8 {
    if (index.* >= text.len) return null;

    const start = index.*;
    const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;

    index.* = if (end < text.len) end + 1 else text.len;

    var line = text[start..end];

    if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

    return line;
}

/// Match one line against a pattern containing `*` and `?` wildcards.
pub fn globMatch(pattern: []const u8, text: []const u8) bool {
    var pattern_index: usize = 0;
    var text_index: usize = 0;
    var star_pattern: ?usize = null;
    var star_text: usize = 0;

    while (text_index < text.len) {
        if (pattern_index < pattern.len and
            (pattern[pattern_index] == '?' or pattern[pattern_index] == text[text_index]))
        {
            pattern_index += 1;
            text_index += 1;
        } else if (pattern_index < pattern.len and pattern[pattern_index] == '*') {
            star_pattern = pattern_index;
            star_text = text_index;
            pattern_index += 1;
        } else if (star_pattern) |star| {
            pattern_index = star + 1;
            star_text += 1;
            text_index = star_text;
        } else {
            return false;
        }
    }

    while (pattern_index < pattern.len and pattern[pattern_index] == '*') pattern_index += 1;

    return pattern_index == pattern.len;
}

const testing = std.testing;

test "transcript: exact match" {
    try testing.expect(compare("a\nb\n", "a\nb\n") == null);
}

test "transcript: missing trailing newline still matches" {
    try testing.expect(compare("a\nb", "a\nb\n") == null);
}

test "transcript: CRLF actual output is accepted" {
    try testing.expect(compare("a\nb\n", "a\r\nb\r\n") == null);
}

test "transcript: changed literal fails" {
    const mismatch = compare("Hello from Korbora\n", "Hello from elsewhere\n").?;

    try testing.expectEqual(1, mismatch.line);
    try testing.expectEqualStrings("Hello from Korbora", mismatch.expected.?);
    try testing.expectEqualStrings("Hello from elsewhere", mismatch.actual.?);
}

test "transcript: extra and missing lines are reported" {
    try testing.expectEqual(2, compare("a\n", "a\nb\n").?.line);
    try testing.expectEqual(2, compare("a\nb\n", "a\n").?.line);
}

test "transcript: empty transcripts match" {
    try testing.expect(compare("", "") == null);
    try testing.expect(compare("", "\n") != null);
}

test "transcript: wildcards" {
    try testing.expect(globMatch("mem: * KiB free", "mem: 128612 KiB free"));
    try testing.expect(globMatch("digest=*", "digest="));
    try testing.expect(globMatch("a?c", "abc"));
    try testing.expect(!globMatch("a?c", "ac"));
    try testing.expect(!globMatch("a?c", "abbc"));
    try testing.expect(globMatch("*", ""));
    try testing.expect(globMatch("*", "anything"));
    try testing.expect(!globMatch("abc", "abcd"));
}
