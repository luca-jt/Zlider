const std = @import("std");
const c = @import("c.zig");
const slides = @import("slides.zig");
const win = @import("window.zig");
const rendering = @import("rendering.zig");

pub fn main() !void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    std.debug.assert(args.skip()); // skip the program name

    var slide_show = slides.SlideShow.init(std.heap.page_allocator);
    defer slide_show.deinit();

    const window = win.initWindow(800, 450, slide_show.title);
    defer win.closeWindow(window);
    win.setEventConfig(window);

    var renderer = try rendering.Renderer.init(std.heap.page_allocator);
    defer renderer.deinit();

    if (args.next()) |file_path| {
        slide_show.loadSlides(file_path);
        renderer.loadSlideData(&slide_show);

        if (args.skip()) {
            @panic("You can only supply one additional command line argument with a file or zero.");
        }
    }

    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        try win.handleInput(window, &slide_show, &renderer);
        try renderer.render(&slide_show);
        c.glfwSwapBuffers(window);
        c.glfwWaitEvents();
    }
}
