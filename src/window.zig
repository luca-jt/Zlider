const target_os = @import("builtin").target.os.tag;
const c = @import("c.zig");
const slide = @import("slides.zig");
const std = @import("std");
const print = std.debug.print;
const String = std.ArrayList(u8);
const Allocator = std.mem.Allocator;
const state = @import("state.zig");

pub const viewport_ratio: f32 = 16.0 / 9.0;
pub const default_title: [:0]const u8 = "Zlider";

pub fn updateWindowAttributes(window: *c.GLFWwindow) void {
    c.glfwGetWindowPos(window, &state.window_state.win_pos_x, &state.window_state.win_pos_y);
    c.glfwGetWindowSize(window, &state.window_state.win_size_x, &state.window_state.win_size_y);
}

fn resizeViewport(width: c_int, height: c_int) void {
    var w = width;
    var h = height;
    var vp_x: c_int = 0;
    var vp_y: c_int = 0;
    const regular_ratio = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));

    if (viewport_ratio < regular_ratio) {
        const forced_width: c_int = @intFromFloat(@as(f32, @floatFromInt(h)) * viewport_ratio);
        vp_x = @divTrunc((w - forced_width), 2);
        w = forced_width;
    } else if (viewport_ratio > regular_ratio) {
        const forced_height: c_int = @intFromFloat(@as(f32, @floatFromInt(w)) / viewport_ratio);
        vp_y = @divTrunc((h - forced_height), 2);
        h = forced_height;
    }

    c.glViewport(vp_x, vp_y, w, h);
    c.glScissor(vp_x, vp_y, w, h);
}

pub fn initWindow(width: c_int, height: c_int) *c.GLFWwindow {
    if (c.glfwInit() == c.GL_FALSE) {
        @panic("Failed to initialize GLFW.");
    }

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 5);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    if (target_os == .macos) {
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    }

    const window = c.glfwCreateWindow(width, height, default_title, null, null) orelse @panic("Failed to create GLFW window.");

    c.glfwMakeContextCurrent(window);
    c.glfwSetWindowSizeLimits(window, 100, 100, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

    if (c.gladLoadGLLoader(@ptrCast(&c.glfwGetProcAddress)) == c.GL_FALSE) {
        @panic("Failed to initialize GLAD.");
    }

    framebufferSizeCallback(window, width, height);

    return window;
}

pub fn closeWindow(window: *c.GLFWwindow) void {
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    resizeViewport(width, height);
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
    const path: [:0]const u8 = std.mem.span(paths[0]); // assumed to be null-terminated

    state.renderer.clear();
    state.slide_show.loadNewSlides(path, window) catch @panic("allocation error");
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
        var c = false;
        var esc = false;
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
        c.GLFW_KEY_C => blk: {
            const flip = pressed and !KeyStates.c or released and KeyStates.c;
            if (flip) KeyStates.c = !KeyStates.c;
            break :blk flip and pressed;
        },
        c.GLFW_KEY_ESCAPE => blk: {
            const flip = pressed and !KeyStates.esc or released and KeyStates.esc;
            if (flip) KeyStates.esc = !KeyStates.esc;
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
    // slide show switch
    if (keyIsPressed(window, c.GLFW_KEY_RIGHT) or keyIsPressed(window, c.GLFW_KEY_DOWN)) {
        if (state.slide_show.slide_index + 1 < state.slide_show.slides.items.len) {
            state.slide_show.slide_index += 1;
        }
    }
    if (keyIsPressed(window, c.GLFW_KEY_LEFT) or keyIsPressed(window, c.GLFW_KEY_UP)) {
        if (state.slide_show.slide_index > 0) {
            state.slide_show.slide_index -= 1;
        }
    }
    // unload the slides
    if (keyIsPressed(window, c.GLFW_KEY_C) and state.slide_show.fileIsTracked()) {
        state.renderer.clear();
        state.slide_show.loadHomeScreenSlide(window);
        state.renderer.loadSlideData(&state.slide_show);
    }
    // dump the slides to png
    if (keyIsPressed(window, c.GLFW_KEY_I) and state.slide_show.fileIsTracked() and state.slide_show.slides.items.len > 0) {
        const current_slide_idx = state.slide_show.slide_index;
        state.slide_show.slide_index = 0;

        const slide_mem_size = @as(usize, @intCast(state.window_state.vp_size_x)) * @as(usize, @intCast(state.window_state.vp_size_y)) * 4;
        const slide_mem = try allocator.allocSentinel(u8, slide_mem_size, 0);
        defer allocator.free(slide_mem);

        var slide_file_name = String.init(allocator);
        defer slide_file_name.deinit();
        try slide_file_name.appendSlice(state.slide_show.loadedFileDir());
        try slide_file_name.append('/');
        try slide_file_name.appendSlice(state.slide_show.loadedFileNameNoExtension());
        try slide_file_name.appendSlice("_000.png");
        try slide_file_name.append(0);

        const number_slice = slide_file_name.items[slide_file_name.items.len-8..slide_file_name.items.len-5];

        while (state.slide_show.slide_index < state.slide_show.slides.items.len) {
            const slide_number = state.slide_show.slide_index + 1;
            _ = std.fmt.bufPrintIntToSlice(number_slice, slide_number, 10, .lower, .{ .width = 3, .fill = '0' });

            try state.renderer.render(&state.slide_show);
            copyFrameBufferToMemory(slide_mem);
            _ = c.stbi_write_png(@ptrCast(slide_file_name.items), state.window_state.vp_size_x, state.window_state.vp_size_y, 4, @ptrCast(slide_mem), state.window_state.vp_size_x * 4);
            print("Dumped slide {} to file '{s}'.\n", .{slide_number, slide_file_name.items[0..slide_file_name.items.len-1]});
            state.slide_show.slide_index += 1;
        }

        state.slide_show.slide_index = current_slide_idx;
    }
    // close the window
    if (keyIsPressed(window, c.GLFW_KEY_ESCAPE)) {
        c.glfwSetWindowShouldClose(window, c.GLFW_TRUE);
    }
}

fn copyFrameBufferToMemory(memory: [:0]u8) void {
    c.glReadPixels(state.window_state.vp_pos_x, state.window_state.vp_pos_y, state.window_state.vp_size_x, state.window_state.vp_size_y, c.GL_RGBA, c.GL_UNSIGNED_BYTE, @ptrCast(memory));
}
