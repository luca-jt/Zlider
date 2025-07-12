const std = @import("std");
const expect = std.testing.expect;
const data = @import("data.zig");

fn checkIteratorOutput(output: ?[]const u8, expected: ?[]const u8) !void {
    if (output == null and expected == null) return;
    if (output != null and expected == null) return error.IteratorExpectedNull;
    if (output == null and expected != null) return error.IteratorExpectedNonNull;
    try expect(std.mem.eql(u8, output.?, expected.?));
}

test "iterator basic" {
    const s = "A|A|A";
    var it: data.SplitIterator = .{ .string = s, .delimiter = '|' };

    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), null);
}

test "iterator special" {
    const s = "|A|A||A|";
    var it: data.SplitIterator = .{ .string = s, .delimiter = '|' };

    try checkIteratorOutput(it.next(), "");
    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), "");
    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), "");
    try checkIteratorOutput(it.next(), null);
}

test "iterator exclude empty slices" {
    const s = "|A|A||A|";
    var it: data.SplitIterator = .{ .string = s, .delimiter = '|', .include_empty_slices = false };

    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), "A");
    try checkIteratorOutput(it.next(), null);
}

test "iterator exclude empty slices peek" {
    const s = "|A|A||A|";
    var it: data.SplitIterator = .{ .string = s, .delimiter = '|', .include_empty_slices = false };

    try checkIteratorOutput(it.peek(0), null);
    try checkIteratorOutput(it.peek(1), "A");
    try checkIteratorOutput(it.peek(4), null);
    try checkIteratorOutput(it.peek(2), "A");
    try checkIteratorOutput(it.peek(3), "A");
}

test "iterator peek" {
    const s = "|A|A||A|";
    var it: data.SplitIterator = .{ .string = s, .delimiter = '|' };

    try checkIteratorOutput(it.peek(0), null);
    try checkIteratorOutput(it.peek(1), "");
    try expect(it.next() != null);
    try checkIteratorOutput(it.peek(2), "A");
    try checkIteratorOutput(it.peek(1), "A");
    try expect(it.next() != null);
    try expect(it.next() != null);
    try checkIteratorOutput(it.peek(1), "");
    try expect(it.next() != null);
    try checkIteratorOutput(it.peek(1), "A");
    try expect(it.next() != null);
    try checkIteratorOutput(it.peek(1), "");
    try expect(it.next() != null);
    try checkIteratorOutput(it.peek(2), null);
    try checkIteratorOutput(it.peek(1), null);
    try expect(it.next() == null);
}
