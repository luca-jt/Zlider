const std = @import("std");
const print = std.debug.print;

const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cInclude("GLFW/glfw3.h");
    @cInclude("glad.c");
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
    @cInclude("stb_truetype.h");
});

pub fn main() !void {
    print("All your {s} are belong to us.\n", .{"codebase"});

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush();
}
