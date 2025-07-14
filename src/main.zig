const std = @import("std");
const c = @import("c.zig");
const win = @import("window.zig");
const slides = @import("slides.zig");
const render = @import("rendering.zig");
const state = @import("state.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    std.debug.assert(args.skip()); // skip the program name

    state.slide_show = try slides.SlideShow.init(allocator);
    defer state.slide_show.deinit();

    try state.window.init();
    defer state.window.destroy();

    c.stbi_flip_vertically_on_write(1);

    state.renderer = try render.Renderer.init(allocator);
    defer state.renderer.deinit();

    if (args.next()) |file_path| {
        try state.slide_show.loadNewSlides(file_path);
        if (args.skip()) @panic("You can only supply one additional command line argument with a file or zero.");
    } else {
        state.slide_show.loadHomeScreenSlide();
    }
    state.renderer.loadSlideData(&state.slide_show);

    while (!state.window.shouldClose()) {
        try win.handleInput(allocator);
        try state.renderer.render(&state.slide_show);
        c.glfwSwapBuffers(state.window.window);
        c.glfwWaitEvents();
    }
}
