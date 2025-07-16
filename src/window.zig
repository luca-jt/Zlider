const target_os = @import("builtin").target.os.tag;
const c = @import("c.zig");
const slides = @import("slides.zig");
const state = @import("state.zig");
const data = @import("data.zig");
const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const String = std.ArrayList(u8);

pub const default_title: [:0]const u8 = "Zlider";
pub const initial_window_width: c_int = 800;
pub const initial_window_height: c_int = 450;
pub const default_viewport_aspect_ratio: f32 = 16.0 / 9.0;
pub const default_viewport_resolution_width_reference: f64 = 1920;
pub var viewport_resolution_width_reference: f64 = default_viewport_resolution_width_reference;
pub const viewport_resolution_height_reference: f64 = 1080; // never changes

pub const Window = extern struct {
    glfw_window: ?*c.GLFWwindow = null,
    forced_viewport_aspect_ratio: f32 = default_viewport_aspect_ratio, // (width / height)
    display_black_bars: bool = false,

    pos_x: c_int = undefined,
    pos_y: c_int = undefined,
    size_x: c_int = initial_window_width,
    size_y: c_int = initial_window_height,
    viewport_pos_x: c_int = 0,
    viewport_pos_y: c_int = 0,
    viewport_size_x: c_int = initial_window_width,
    viewport_size_y: c_int = initial_window_height,

    const Self = @This();

    pub fn init(self: *Self) !void {
        if (c.glfwInit() == c.GL_FALSE) {
            return error.GLFWInitFailed;
        }

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 5);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

        if (target_os == .macos) {
            c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
        }

        const window = c.glfwCreateWindow(initial_window_width, initial_window_height, default_title, null, null) orelse return error.GLFWWindowCreationFailed;

        c.glfwMakeContextCurrent(window);
        c.glfwSetWindowSizeLimits(window, initial_window_width / 2, initial_window_height / 2, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

        if (c.gladLoadGLLoader(@ptrCast(&c.glfwGetProcAddress)) == c.GL_FALSE) {
            return error.GladInitFailed;
        }

        // set the event config
        c.glfwSetInputMode(window, c.GLFW_LOCK_KEY_MODS, c.GLFW_TRUE);
        c.glfwSetInputMode(window, c.GLFW_STICKY_KEYS, c.GLFW_TRUE);
        _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
        _ = c.glfwSetWindowPosCallback(window, windowPosCallback);
        _ = c.glfwSetDropCallback(window, dropCallback);

        self.glfw_window = window;
        self.updatePosition();
        self.updateSize();
        self.updateViewport(initial_window_width, initial_window_height);
    }

    pub fn updateTitle(self: *Self, title: ?[]const u8) void {
        if (title) |t| {
            c.glfwSetWindowTitle(self.glfw_window, @ptrCast(t)); // assumed to be null-terminated
        } else {
            c.glfwSetWindowTitle(self.glfw_window, default_title);
        }
    }

    pub fn updatePosition(self: *Self) void {
        c.glfwGetWindowPos(self.glfw_window, &self.pos_x, &self.pos_y);
    }

    pub fn updateSize(self: *Self) void {
        c.glfwGetWindowSize(self.glfw_window, &self.size_x, &self.size_y);
    }

    pub fn updateViewport(self: *Self, width: c_int, height: c_int) void {
        var w = width;
        var h = height;
        var vp_x: c_int = 0;
        var vp_y: c_int = 0;
        const regular_ratio = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
        const viewport_ratio = self.forced_viewport_aspect_ratio;

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
        if (self.display_black_bars) {
            c.glScissor(vp_x, vp_y, w, h);
        } else {
            c.glScissor(0, 0, width, height);
        }

        c.glGetIntegerv(c.GL_VIEWPORT, &self.viewport_pos_x); // this overwrites both viewport position and size
    }

    pub fn clearScreen(self: *const Self, color: data.Color32) void {
        c.glScissor(0, 0, self.size_x, self.size_y);
        c.glClearColor(0, 0, 0, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        if (self.display_black_bars) {
            c.glScissor(self.viewport_pos_x, self.viewport_pos_y, self.viewport_size_x, self.viewport_size_y);
        }
        const float_color = color.toVec4();
        c.glClearColor(float_color.x, float_color.y, float_color.z, float_color.w);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    }

    pub fn shouldClose(self: *const Self) bool {
        return c.glfwWindowShouldClose(self.glfw_window) != c.GL_FALSE;
    }

    pub fn close(self: *const Self) void {
        c.glfwSetWindowShouldClose(self.glfw_window, c.GLFW_TRUE);
    }

    pub fn destroy(self: Self) void {
        c.glfwDestroyWindow(self.glfw_window);
        c.glfwTerminate();
    }

    pub fn forceViewportAspectRatio(self: *Self, aspect: ?f32) void {
        if (aspect) |forced_aspect| {
            self.forced_viewport_aspect_ratio = forced_aspect;
            viewport_resolution_width_reference = viewport_resolution_height_reference * forced_aspect;
        } else {
            self.forced_viewport_aspect_ratio = default_viewport_aspect_ratio;
            viewport_resolution_width_reference = default_viewport_resolution_width_reference;
        }
    }

    /// width / height
    pub fn viewportRatio(self: *const Self) f32 {
        return @as(f32, @floatFromInt(self.viewport_size_x)) / @as(f32, @floatFromInt(self.viewport_size_y));
    }

    fn writeFrameBufferToMemory(self: *const Self, memory: [:0]u8, comptime channels: usize) !void {
        const byte_format = if (channels == 3) c.GL_RGB else if (channels == 4) c.GL_RGBA else @compileError("Channel number not supported.");

        const temp_mem = try state.allocator.allocSentinel(u8, memory.len, 0);
        defer state.allocator.free(temp_mem);

        c.glPixelStorei(c.GL_PACK_ALIGNMENT, 1);
        c.glReadPixels(self.viewport_pos_x, self.viewport_pos_y, self.viewport_size_x, self.viewport_size_y, byte_format, c.GL_UNSIGNED_BYTE, @ptrCast(temp_mem));

        // flip the image vertically
        const row_length: usize = @as(usize, @intCast(self.viewport_size_x)) * channels;
        for (0..@intCast(self.viewport_size_y)) |i| {
            const source_row_start = i * row_length;
            const target_row_start = (@as(usize, @intCast(self.viewport_size_y)) - 1 - i) * row_length;
            const source_row = temp_mem[source_row_start..source_row_start + row_length];
            const target_row = memory[target_row_start..target_row_start + row_length];
            @memcpy(target_row, source_row);
        }
    }

    fn toggleFullscreen(self: *Self) void {
        const monitor = c.glfwGetPrimaryMonitor();
        if (c.glfwGetWindowMonitor(self.glfw_window) == null) {
            self.updatePosition();
            self.updateSize();
            const mode = c.glfwGetVideoMode(monitor);
            c.glfwSetWindowMonitor(self.glfw_window, monitor, 0, 0, mode[0].width, mode[0].height, c.GLFW_DONT_CARE);
        } else {
            c.glfwSetWindowMonitor(self.glfw_window, null, self.pos_x, self.pos_y, self.size_x, self.size_y, c.GLFW_DONT_CARE);
        }
    }
};

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    _ = window;
    state.window.updateSize();
    state.window.updateViewport(width, height);
    state.renderer.updateMatrices();
}

fn windowPosCallback(window: ?*c.GLFWwindow, xpos: c_int, ypos: c_int) callconv(.c) void {
    _ = window;
    state.window.pos_x = xpos;
    state.window.pos_y = ypos;
}

fn dropCallback(window: ?*c.GLFWwindow, path_count: c_int, paths: [*c][*c]const u8) callconv(.c) void {
    _ = window;
    if (path_count != 1) return;
    const path: [:0]const u8 = std.mem.span(paths[0]); // assumed to be null-terminated

    state.renderer.clear();
    slides.loadSlideShow(path) catch @panic("allocation error");
    state.renderer.loadSlideData();
}

fn keyIsPressed(key: c_int) bool {
    const KeyStates = struct {
        var f11 = false;
        var left = false;
        var right = false;
        var up = false;
        var down = false;
        var i = false;
        var c = false;
        var esc = false;
        var p = false;
        var l = false;
    };

    const event = c.glfwGetKey(state.window.glfw_window, key);
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
        c.GLFW_KEY_P => blk: {
            const flip = pressed and !KeyStates.p or released and KeyStates.p;
            if (flip) KeyStates.p = !KeyStates.p;
            break :blk flip and pressed;
        },
        c.GLFW_KEY_L => blk: {
            const flip = pressed and !KeyStates.l or released and KeyStates.l;
            if (flip) KeyStates.l = !KeyStates.l;
            break :blk flip and pressed;
        },
        else => false,
    };
}

pub fn handleInput() !void {
    // toggle fullscreen
    if (keyIsPressed(c.GLFW_KEY_F11)) {
        state.window.toggleFullscreen();
    }

    // slide show switch
    if (keyIsPressed(c.GLFW_KEY_RIGHT) or keyIsPressed(c.GLFW_KEY_DOWN)) {
        if (state.slide_show.slide_index + 1 < state.slide_show.slides.items.len) {
            state.slide_show.slide_index += 1;
        }
    }
    if (keyIsPressed(c.GLFW_KEY_LEFT) or keyIsPressed(c.GLFW_KEY_UP)) {
        if (state.slide_show.slide_index > 0) {
            state.slide_show.slide_index -= 1;
        }
    }

    // unload the slides
    if (keyIsPressed(c.GLFW_KEY_C) and state.slide_show.fileIsTracked()) {
        state.renderer.clear();
        slides.loadHomeScreenSlide();
        state.renderer.loadSlideData();
    }

    // dump the slides to png
    if (keyIsPressed(c.GLFW_KEY_I) and state.slide_show.fileIsTracked() and state.slide_show.slides.items.len > 0) {
        const current_slide_idx = state.slide_show.slide_index;
        state.slide_show.slide_index = 0;

        const channels: usize = 4;
        const slide_mem_size = @as(usize, @intCast(state.window.viewport_size_x)) * @as(usize, @intCast(state.window.viewport_size_y)) * channels;
        const slide_mem = try state.allocator.allocSentinel(u8, slide_mem_size, 0);
        defer state.allocator.free(slide_mem);

        var slide_file_name = String.init(state.allocator);
        defer slide_file_name.deinit();
        try slide_file_name.appendSlice(state.slide_show.loadedFileDir());
        try slide_file_name.append('/');
        try slide_file_name.appendSlice(state.slide_show.loadedFileNameNoExtension());
        try slide_file_name.appendSlice("_000.png");
        try slide_file_name.append(0);

        const number_slice = slide_file_name.items[slide_file_name.items.len-8..slide_file_name.items.len-5];
        var slide_number: usize = 1;

        while (state.slide_show.slide_index < state.slide_show.slides.items.len) : (state.slide_show.slide_index += 1) {
            if (state.slide_show.currentSlide().has_fallthrough_successor) continue;

            _ = std.fmt.bufPrintIntToSlice(number_slice, slide_number, 10, .lower, .{ .width = 3, .fill = '0' });

            try state.renderer.render();
            try state.window.writeFrameBufferToMemory(slide_mem, channels);

            _ = c.stbi_write_png(@ptrCast(slide_file_name.items), state.window.viewport_size_x, state.window.viewport_size_y, 4, @ptrCast(slide_mem), state.window.viewport_size_x * 4);
            print("Dumped slide {} to image file '{s}'.\n", .{slide_number, slide_file_name.items});

            slide_number += 1;
        }

        state.slide_show.slide_index = current_slide_idx;
    }

    // close the window
    if (keyIsPressed(c.GLFW_KEY_ESCAPE)) {
        state.window.close();
    }

    // dump the slides to PDF
    if (keyIsPressed(c.GLFW_KEY_P) and state.slide_show.fileIsTracked() and state.slide_show.slides.items.len > 0) {
        const compress_slides = true;
        try dumpSlidesPDF(compress_slides);
    }
    if (keyIsPressed(c.GLFW_KEY_L) and state.slide_show.fileIsTracked() and state.slide_show.slides.items.len > 0) {
        const compress_slides = false;
        try dumpSlidesPDF(compress_slides);
    }
}

fn dumpSlidesPDF(compress_slides: bool) !void {
    const current_slide_idx = state.slide_show.slide_index;
    state.slide_show.slide_index = 0;

    const channels: usize = 3;
    const slide_mem_size = @as(usize, @intCast(state.window.viewport_size_x)) * @as(usize, @intCast(state.window.viewport_size_y)) * channels;
    const slide_mem = try state.allocator.allocSentinel(u8, slide_mem_size, 0);
    defer state.allocator.free(slide_mem);

    var pdf_file_name = String.init(state.allocator);
    defer pdf_file_name.deinit();
    try pdf_file_name.appendSlice(state.slide_show.loadedFileDir());
    try pdf_file_name.append('/');
    try pdf_file_name.appendSlice(state.slide_show.loadedFileNameNoExtension());
    if (compress_slides) try pdf_file_name.appendSlice("_compressed");
    try pdf_file_name.appendSlice(".pdf");
    try pdf_file_name.append(0);

    var pdf_info: c.pdf_info = .{
        .creator = data.extendStringToArrayZeroed(64, "Zlider"),
        .producer = data.extendStringToArrayZeroed(64, "Zlider"),
        .title = [_]u8{0} ** 64,
        .author = data.extendStringToArrayZeroed(64, "Zlider"),
        .subject = data.extendStringToArrayZeroed(64, "Generated Zlider slide show"),
        .date = [_]u8{0} ** 64,
    };
    _ = std.fmt.bufPrint(&pdf_info.title, "{s}", .{ state.slide_show.loadedFileNameNoExtension() }) catch .{}; // we don't care if the name is too long and just continue
    var now: c.time_t = undefined;
    _ = c.time(&now);
    _ = std.fmt.bufPrint(&pdf_info.date, "{s}", .{ std.mem.span(c.asctime(c.localtime(&now))) }) catch unreachable;

    const pdf_width: f32 = @floatFromInt(state.window.viewport_size_x);
    const pdf_height: f32 = @floatFromInt(state.window.viewport_size_y);
    const pdf = c.pdf_create(pdf_width, pdf_height, &pdf_info);

    while (state.slide_show.slide_index < state.slide_show.slides.items.len) : (state.slide_show.slide_index += 1) {
        if (state.slide_show.currentSlide().has_fallthrough_successor and compress_slides) continue;

        try state.renderer.render();
        try state.window.writeFrameBufferToMemory(slide_mem, channels);
        _ = c.pdf_append_page(pdf);
        assert(c.pdf_add_rgb24(pdf, null, 0, 0, pdf_width, pdf_height, slide_mem, @intCast(state.window.viewport_size_x), @intCast(state.window.viewport_size_y)) >= 0);
    }

    assert(c.pdf_save(pdf, @ptrCast(pdf_file_name.items)) >= 0);
    print("Dumped slide show to PDF file: '{s}'.\n", .{ pdf_file_name.items });
    c.pdf_destroy(pdf);
    state.slide_show.slide_index = current_slide_idx;
}
