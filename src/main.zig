const std = @import("std");
const c = @import("c.zig");
const win = @import("window.zig");
const slides = @import("slides.zig");
const render = @import("rendering.zig");
const state = @import("state.zig");

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
        if (args.skip()) @panic("You can only supply one additional command line argument with a file or zero.");
    } else {
        slides.loadHomeScreenSlide();
    }

    while (!state.window.shouldClose()) {
        try win.handleInput();
        try state.renderer.render();
        state.window.swapBuffers();
        c.glfwWaitEvents();
    }
}
