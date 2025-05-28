const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig");
const data = @import("data.zig");
const win = @import("window.zig");

pub fn main() !void {
    var arg_allocator = std.heap.GeneralPurposeAllocator(.{}).init;
    var args = try std.process.argsWithAllocator(arg_allocator.allocator());
    defer args.deinit();
    assert(args.skip()); // skip the program name

    var slide_show: ?data.SlideShow = null;
    //defer drop_slide_show(&slide_show);

    if (args.next()) |title| {
        slide_show = .{
            .title = title,
            .slides = std.ArrayList(data.Slide).init(std.heap.page_allocator),
        };

        if (args.skip()) {
            @panic("You can only supply one additional command line argument with a file or zero.");
        }
    }

    const window: *c.GLFWwindow = win.init_window(800, 600, "Clider");
    defer win.close_window(window);

    win.set_event_config(window);
    if (slide_show) |show| {
        c.glfwSetWindowTitle(window, show.title);
    }

    //var renderer: Renderer = .{};
    //renderer.init(&slide_show);
    //defer renderer.deinit();

    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        //handle_input(window, &slide_show, &renderer);
        //renderer.render(&slide_show);
        c.glfwSwapBuffers(window);
        c.glfwWaitEvents();
    }
}
