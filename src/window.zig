const target_os = @import("builtin").target.os.tag;
const c = @import("c.zig");
const slide = @import("slides.zig");
const std = @import("std");
const String = std.ArrayList(u8);
const Allocator = std.mem.Allocator;
const state = @import("state.zig");

pub const viewport_ratio: f32 = 16.0 / 9.0;

pub fn updateWindowAttributes(window: *c.GLFWwindow) void {
    c.glfwGetWindowPos(window, &state.window_state.win_pos_x, &state.window_state.win_pos_y);
    c.glfwGetWindowSize(window, &state.window_state.win_size_x, &state.window_state.win_size_y);
}

fn resizeViewport(width: u32, height: u32) void {
    var w = width;
    var h = height;
    var vp_x: u32 = 0;
    var vp_y: u32 = 0;
    const regular_ratio = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));

    if (viewport_ratio < regular_ratio) {
        const forced_width: u32 = @intFromFloat(@as(f32, @floatFromInt(h)) * viewport_ratio);
        vp_x = (w / forced_width) / 2;
        w = forced_width;
    } else {
        const forced_height: u32 = @intFromFloat(@as(f32, @floatFromInt(w)) / viewport_ratio);
        vp_y = (h / forced_height) / 2;
        h = forced_height;
    }

    c.glViewport(@intCast(vp_x), @intCast(vp_y), @intCast(w), @intCast(h));
    c.glScissor(@intCast(vp_x), @intCast(vp_y), @intCast(w), @intCast(h));
}

pub fn initWindow(width: u32, height: u32, title: [:0]const u8) *c.GLFWwindow {
    if (c.glfwInit() == c.GL_FALSE) {
        @panic("Failed to initialize GLFW.");
    }

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 5);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    if (target_os == .macos) {
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    }

    const window = c.glfwCreateWindow(@intCast(width), @intCast(height), title, null, null) orelse @panic("Failed to create GLFW window.");

    c.glfwMakeContextCurrent(window);
    c.glfwSetWindowSizeLimits(window, 100, 100, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

    if (c.gladLoadGLLoader(@ptrCast(&c.glfwGetProcAddress)) == c.GL_FALSE) {
        @panic("Failed to initialize GLAD.");
    }

    resizeViewport(width, height);

    return window;
}

pub fn closeWindow(window: *c.GLFWwindow) void {
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    resizeViewport(@intCast(width), @intCast(height));
    c.glGetIntegerv(c.GL_VIEWPORT, &state.window_state.vp_pos_x); // this overwrites both viewport position and size
    c.glfwGetWindowSize(window, &state.window_state.win_size_x, &state.window_state.win_size_y);
}

fn windowPosCallback(window: ?*c.GLFWwindow, xpos: c_int, ypos: c_int) callconv(.c) void {
    _ = xpos; // to suppress errors
    _ = ypos;
    c.glfwGetWindowPos(window, &state.window_state.win_pos_x, &state.window_state.win_pos_y);
}

fn dropCallback(window: ?*c.GLFWwindow, path_count: c_int, paths: [*c][*c]const u8) callconv(.c) void {
    if (path_count != 1) return;
    _ = window;
    const path: [:0]const u8 = std.mem.span(paths[0]); // assumed to be null-terminated

    std.log.info("Dropped slides file: {s}", .{path});
    state.renderer.clear();
    state.slide_show.loadSlides(path);
    state.renderer.loadSlideData(&state.slide_show);
}

pub fn setEventConfig(window: *c.GLFWwindow) void {
    c.glfwSetInputMode(window, c.GLFW_LOCK_KEY_MODS, c.GLFW_TRUE);
    c.glfwSetInputMode(window, c.GLFW_STICKY_KEYS, c.GLFW_TRUE);
    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
    _ = c.glfwSetWindowPosCallback(window, windowPosCallback);
    _ = c.glfwSetDropCallback(window, dropCallback);
}

fn keyIsPressed(window: *c.GLFWwindow, key: c_int) bool {
    const KeyStates = struct {
        var f11 = false;
        var left = false;
        var right = false;
        var up = false;
        var down = false;
        var i = false;
    };

    const event = c.glfwGetKey(window, key);
    const pressed = event == c.GLFW_PRESS;
    const released = event == c.GLFW_RELEASE;

    return switch (key) {
        c.GLFW_KEY_F11 => blk: {
            const flip = pressed and !KeyStates.f11 or released and KeyStates.f11;
            if (flip) KeyStates.f11 = !KeyStates.f11;
            break :blk flip and pressed;
        },
        c.GLFW_KEY_I => blk: {
            const flip = pressed and !KeyStates.i or released and KeyStates.i;
            if (flip) KeyStates.i = !KeyStates.i;
            break :blk flip and pressed;
        },
        c.GLFW_KEY_LEFT => blk: {
            const flip = pressed and !KeyStates.left or released and KeyStates.left;
            if (flip) KeyStates.left = !KeyStates.left;
            break :blk flip and pressed;
        },
        c.GLFW_KEY_RIGHT => blk: {
            const flip = pressed and !KeyStates.right or released and KeyStates.right;
            if (flip) KeyStates.right = !KeyStates.right;
            break :blk flip and pressed;
        },
        c.GLFW_KEY_UP => blk: {
            const flip = pressed and !KeyStates.up or released and KeyStates.up;
            if (flip) KeyStates.up = !KeyStates.up;
            break :blk flip and pressed;
        },
        c.GLFW_KEY_DOWN => blk: {
            const flip = pressed and !KeyStates.down or released and KeyStates.down;
            if (flip) KeyStates.down = !KeyStates.down;
            break :blk flip and pressed;
        },
        else => false,
    };
}

pub fn handleInput(window: *c.GLFWwindow, allocator: Allocator) !void {
    // fullscreen toggle
    if (keyIsPressed(window, c.GLFW_KEY_F11)) {
        const monitor = c.glfwGetPrimaryMonitor();
        if (c.glfwGetWindowMonitor(window) == null) {
            updateWindowAttributes(window);
            const mode = c.glfwGetVideoMode(monitor);
            c.glfwSetWindowMonitor(window, monitor, 0, 0, mode[0].width, mode[0].height, c.GLFW_DONT_CARE);
        } else {
            c.glfwSetWindowMonitor(window, null, state.window_state.win_pos_x, state.window_state.win_pos_y, state.window_state.win_size_x, state.window_state.win_size_y, c.GLFW_DONT_CARE);
        }
    }
    // slide_show_switch
    if (keyIsPressed(window, c.GLFW_KEY_RIGHT) or keyIsPressed(window, c.GLFW_KEY_DOWN)) {
        if (state.slide_show.slide_index < state.slide_show.slides.items.len - 1) {
            state.slide_show.slide_index += 1;
        }
    }
    if (keyIsPressed(window, c.GLFW_KEY_LEFT) or keyIsPressed(window, c.GLFW_KEY_UP)) {
        if (state.slide_show.slide_index > 0) {
            state.slide_show.slide_index -= 1;
        }
    }
    // dump the slides to png
    if (keyIsPressed(window, c.GLFW_KEY_I)) {
        const current_slide_idx = state.slide_show.slide_index;
        state.slide_show.slide_index = 0;

        const slide_mem_size = @as(usize, @intCast(state.window_state.vp_size_x)) * @as(usize, @intCast(state.window_state.vp_size_y)) * 4;
        const slide_mem = try allocator.allocSentinel(u8, slide_mem_size, 0);
        defer allocator.free(slide_mem);

        const compression_level = 5;

        var slide_file_name = String.init(allocator);
        defer slide_file_name.deinit();
        try slide_file_name.appendSlice(state.slide_show.title);
        try slide_file_name.appendSlice("_000");
        try slide_file_name.append(0);

        const number_slice = slide_file_name.items[slide_file_name.items.len-4..slide_file_name.items.len-1];

        while (state.slide_show.slide_index < state.slide_show.slides.items.len) {
            const slide_number = state.slide_show.slide_index + 1;
            _ = std.fmt.bufPrintIntToSlice(number_slice, slide_number, 10, .lower, .{ .width = 3, .fill = '0' });

            try state.renderer.render(&state.slide_show);
            copyFrameBufferToMemory(slide_mem);

            _ = c.stbi_write_png(@ptrCast(slide_file_name.items), state.window_state.vp_size_x, state.window_state.vp_size_y, compression_level, @ptrCast(slide_mem), 4);
            state.slide_show.slide_index += 1;
        }

        state.slide_show.slide_index = current_slide_idx;
    }
}

fn copyFrameBufferToMemory(memory: [:0]u8) void {
    c.glReadBuffer(c.GL_FRONT); // TODO: or GL_BACK?
    // TODO: (0,0) of the window or the viewport?
    c.glReadPixels(0, 0, state.window_state.vp_size_x, state.window_state.vp_size_y, c.GL_RGBA, c.GL_UNSIGNED_BYTE, @ptrCast(memory));
    // TODO: flip the image vertically?
}
