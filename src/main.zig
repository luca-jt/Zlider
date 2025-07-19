const std = @import("std");
const c = @import("c.zig");
const win = @import("window.zig");
const slides = @import("slides.zig");
const render = @import("rendering.zig");
const state = @import("state.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = colorLogFn,
};

pub fn main() !void {
    var args = try std.process.argsWithAllocator(state.allocator);
    defer args.deinit();
    std.debug.assert(args.skip()); // skip the program name

    state.slide_show = try slides.SlideShow.init();
    defer state.slide_show.deinit();

    try state.window.init();
    defer state.window.destroy();

    state.renderer = try render.Renderer.init();
    defer state.renderer.deinit();

    if (args.next()) |file_path| {
        try slides.loadSlideShow(file_path);
        if (args.skip()) {
            std.log.warn("You can only supply one additional command line argument with a file or zero.", .{});
            return;
        }
    } else {
        slides.loadHomeScreenSlide();
    }

    while (!state.window.shouldClose()) {
        try win.handleEvents();
        try state.renderer.render();
        state.window.swapBuffers();
        c.glfwWaitEvents();
    }
}

fn colorLogFn(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    _ = scope;

    const prefix = "[" ++ comptime level.asText() ++ "] ";
    const color = switch (level) {
        .err => "\x1b[0;31m", // red
        .warn => "\x1b[0;33m", // yellow
        .info => "\x1b[0;32m", // green
        .debug => "\x1b[0;34m", // blue
    };
    const color_reset = "\x1b[0m";

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(color ++ prefix ++ color_reset ++ format ++ "\n", args) catch return;
}
