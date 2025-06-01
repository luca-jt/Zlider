const std = @import("std");
const c = @import("c.zig");
const slides = @import("slides.zig");
const win = @import("window.zig");
const rendering = @import("rendering.zig");
const state = @import("state.zig");

pub fn main() !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = alloc.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    std.debug.assert(args.skip()); // skip the program name

    state.slide_show = slides.SlideShow.init(allocator);
    defer state.slide_show.deinit();

    const window = win.initWindow(800, 450, state.slide_show.title);
    defer win.closeWindow(window);
    win.setEventConfig(window);

    state.renderer = try rendering.Renderer.init(allocator);
    defer state.renderer.deinit();

    if (args.next()) |file_path| {
        state.slide_show.loadSlides(file_path);
        state.renderer.loadSlideData(&state.slide_show);

        if (args.skip()) {
            @panic("You can only supply one additional command line argument with a file or zero.");
        }
    }

    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        try win.handleInput(window, allocator);
        try state.renderer.render(&state.slide_show);
        c.glfwSwapBuffers(window);
        c.glfwWaitEvents();
    }
}
