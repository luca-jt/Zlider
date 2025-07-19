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
pub const default_viewport_width_reference: f64 = 1920;
pub var viewport_width_reference: f64 = default_viewport_width_reference;
pub const viewport_height_reference: f64 = 1080; // never changes

pub const Window = extern struct {
    glfw_window: ?*c.GLFWwindow = null,
    forced_viewport_aspect_ratio: f32 = default_viewport_aspect_ratio, // (width / height)
    display_black_bars: bool = false,
    fullscreen: bool = false,

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

    pub fn swapBuffers(self: *const Self) void {
        c.glfwSwapBuffers(self.glfw_window);
    }

    pub fn forceViewportAspectRatio(self: *Self, aspect: ?f32) void {
        if (aspect) |forced_aspect| {
            self.forced_viewport_aspect_ratio = forced_aspect;
            viewport_width_reference = viewport_height_reference * forced_aspect;
        } else {
            self.forced_viewport_aspect_ratio = default_viewport_aspect_ratio;
            viewport_width_reference = default_viewport_width_reference;
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

    /// no desired after-state is just a toggle
    fn setFullscreen(self: *Self, desired: ?bool) void {
        const after = if (desired) |d| d else !self.fullscreen;
        if (after == self.fullscreen) return;

        if (!self.fullscreen) {
            self.updatePosition();
            self.updateSize();
            const monitor = self.getWindowMonitor();
            const mode = c.glfwGetVideoMode(monitor);
            c.glfwSetWindowMonitor(self.glfw_window, monitor, 0, 0, mode.*.width, mode.*.height, c.GLFW_DONT_CARE);
        } else {
            c.glfwSetWindowMonitor(self.glfw_window, null, self.pos_x, self.pos_y, self.size_x, self.size_y, c.GLFW_DONT_CARE);
        }
        self.fullscreen = !self.fullscreen;
    }

    /// get the monitor the window is currently on
    fn getWindowMonitor(self: *Self) *c.GLFWmonitor {
        var monitor: ?*c.GLFWmonitor = null;
        var max_overlap_area: c_int = 0;

        var monitors_size: c_int = undefined;
        const monitors = c.glfwGetMonitors(&monitors_size);

        for (0..@intCast(monitors_size)) |i| {
            var monitor_pos_x: c_int = undefined;
            var monitor_pos_y: c_int = undefined;
            c.glfwGetMonitorPos(monitors[i], &monitor_pos_x, &monitor_pos_y);

            const monitor_video_mode = c.glfwGetVideoMode(monitors[i]);
            const monitor_size_x: c_int = monitor_video_mode.*.width;
            const monitor_size_y: c_int = monitor_video_mode.*.height;

            const window_intersects_monitor = !(
                self.pos_x + self.size_x < monitor_pos_x or
                self.pos_x > monitor_pos_x + monitor_size_x or
                self.pos_y + self.size_y < monitor_pos_y or
                self.pos_y > monitor_pos_y + monitor_size_y
            );

            if (window_intersects_monitor) {
                const intersect_size_x = if (self.pos_x < monitor_pos_x)
                    if (self.pos_x + self.size_x < monitor_pos_x + monitor_size_x)
                        self.pos_x + self.size_x - monitor_pos_x
                    else
                        monitor_size_x
                else
                    if (monitor_pos_x + monitor_size_x < self.pos_x + self.size_x)
                        (monitor_pos_x + monitor_size_x) - self.pos_x
                    else
                        self.size_x;

                const intersect_size_y = if (self.pos_y < monitor_pos_y)
                    if (self.pos_y + self.size_y < monitor_pos_y + monitor_size_y)
                        self.pos_y + self.size_y - monitor_pos_y
                    else
                        monitor_size_y
                else
                    if (monitor_pos_y + monitor_size_y < self.pos_y + self.size_y)
                        monitor_pos_y + monitor_size_y - self.pos_y
                    else
                        self.size_y;

                const overlap_area = intersect_size_x * intersect_size_y;

                if (overlap_area > max_overlap_area) {
                    monitor = monitors[i];
                    max_overlap_area = overlap_area;
                }
            }
        }
        return monitor.?;
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

    slides.loadSlideShow(path) catch @panic("allocation error");
}

const KeyState = struct {
    const keys = [_]c_int{ c.GLFW_KEY_F11, c.GLFW_KEY_I, c.GLFW_KEY_LEFT, c.GLFW_KEY_RIGHT, c.GLFW_KEY_UP, c.GLFW_KEY_DOWN, c.GLFW_KEY_C, c.GLFW_KEY_ESCAPE, c.GLFW_KEY_P, c.GLFW_KEY_LEFT_CONTROL };
    var states = [_]bool{ false } ** keys.len;
    var pressed = [_]bool{ false } ** keys.len;

    fn update() void {
        for (keys, 0..) |key, i| {
            const event = c.glfwGetKey(state.window.glfw_window, key);
            const press = event == c.GLFW_PRESS;
            const release = event == c.GLFW_RELEASE;
            const flip = press and !states[i] or release and states[i];

            if (flip) states[i] = !states[i];
            pressed[i] = flip and press;
        }
    }

    fn isPressed(comptime key: c_int) bool {
        inline for (keys, 0..) |k, i| {
            if (key == k) return pressed[i];
        }
        return false;
    }

    fn isHeld(comptime key: c_int) bool {
        inline for (keys, 0..) |k, i| {
            if (key == k) return states[i];
        }
        return false;
    }
};

pub fn handleInput() !void {
    KeyState.update();

    if (KeyState.isPressed(c.GLFW_KEY_F11)) {
        state.window.setFullscreen(null);
    }

    if (KeyState.isPressed(c.GLFW_KEY_RIGHT) or KeyState.isPressed(c.GLFW_KEY_DOWN)) {
        if (state.slide_show.slide_index + 1 < state.slide_show.slides.items.len) {
            state.slide_show.slide_index += 1;
        }
    }
    if (KeyState.isPressed(c.GLFW_KEY_LEFT) or KeyState.isPressed(c.GLFW_KEY_UP)) {
        if (state.slide_show.slide_index > 0) {
            state.slide_show.slide_index -= 1;
        }
    }

    if (KeyState.isPressed(c.GLFW_KEY_C) and state.slide_show.fileIsTracked()) {
        slides.loadHomeScreenSlide();
    }

    if (KeyState.isPressed(c.GLFW_KEY_I) and state.slide_show.fileIsTracked() and state.slide_show.containsSlides()) {
        const compress_slides = KeyState.isHeld(c.GLFW_KEY_LEFT_CONTROL);
        try dumpSlidesPNG(compress_slides);
    }

    if (KeyState.isPressed(c.GLFW_KEY_ESCAPE)) {
        state.window.close();
    }

    if (KeyState.isPressed(c.GLFW_KEY_P) and state.slide_show.fileIsTracked() and state.slide_show.containsSlides()) {
        const compress_slides = KeyState.isHeld(c.GLFW_KEY_LEFT_CONTROL);
        try dumpSlidesPDF(compress_slides);
    }
}

fn dumpSlidesPNG(compress_slides: bool) !void {
    // save the current state
    const current_slide_idx = state.slide_show.slide_index;
    state.slide_show.slide_index = 0;
    const old_fullscreen = state.window.fullscreen;
    state.window.setFullscreen(false);
    const old_window_width = state.window.size_x;
    const old_window_height = state.window.size_y;
    c.glfwSetWindowSize(state.window.glfw_window, @intFromFloat(viewport_width_reference), @intFromFloat(viewport_height_reference));

    // actual work
    const channels: usize = 4;
    const slide_mem_size = @as(usize, @intCast(state.window.viewport_size_x)) * @as(usize, @intCast(state.window.viewport_size_y)) * channels;
    const slide_mem = try state.allocator.allocSentinel(u8, slide_mem_size, 0);
    defer state.allocator.free(slide_mem);

    var slide_file_name = String.init(state.allocator);
    defer slide_file_name.deinit();
    try slide_file_name.appendSlice(state.slide_show.loadedFileDir());
    try slide_file_name.append('/');
    try slide_file_name.appendSlice(state.slide_show.loadedFileNameNoExtension());
    if (compress_slides) try slide_file_name.appendSlice("_compressed");
    try slide_file_name.appendSlice("_000.png");
    try slide_file_name.append(0);

    const number_slice = slide_file_name.items[slide_file_name.items.len-8..slide_file_name.items.len-5];
    var slide_number: usize = 1;

    while (state.slide_show.slide_index < state.slide_show.slides.items.len) : (state.slide_show.slide_index += 1) {
        if (state.slide_show.currentSlide().?.has_fallthrough_successor and compress_slides) continue;

        _ = std.fmt.bufPrintIntToSlice(number_slice, slide_number, 10, .lower, .{ .width = 3, .fill = '0' });

        try state.renderer.render();
        try state.window.writeFrameBufferToMemory(slide_mem, channels);
        state.window.swapBuffers(); // for animation

        _ = c.stbi_write_png(@ptrCast(slide_file_name.items), state.window.viewport_size_x, state.window.viewport_size_y, channels, @ptrCast(slide_mem), state.window.viewport_size_x * @as(c_int, channels));
        print("Dumped slide {} to image file '{s}'.\n", .{slide_number, slide_file_name.items});

        slide_number += 1;
    }

    // load the original state
    c.glfwSetWindowSize(state.window.glfw_window, old_window_width, old_window_height);
    state.window.setFullscreen(old_fullscreen);
    state.slide_show.slide_index = current_slide_idx;
}

fn dumpSlidesPDF(compress_slides: bool) !void {
    // save the current state
    const current_slide_idx = state.slide_show.slide_index;
    state.slide_show.slide_index = 0;
    const old_fullscreen = state.window.fullscreen;
    state.window.setFullscreen(false);
    const old_window_width = state.window.size_x;
    const old_window_height = state.window.size_y;
    c.glfwSetWindowSize(state.window.glfw_window, @intFromFloat(viewport_width_reference), @intFromFloat(viewport_height_reference));

    // actual work
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
        .producer = data.extendStringToArrayZeroed(64, "https://github.com/luca-jt/Zlider"),
        .title = [_]u8{0} ** 64,
        .author = data.extendStringToArrayZeroed(64, "Zlider"),
        .subject = data.extendStringToArrayZeroed(64, "Generated Zlider Slide Show"),
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
        if (state.slide_show.currentSlide().?.has_fallthrough_successor and compress_slides) continue;

        try state.renderer.render();
        try state.window.writeFrameBufferToMemory(slide_mem, channels);
        state.window.swapBuffers(); // for animation

        _ = c.pdf_append_page(pdf);
        var png_len: c_int = undefined;
        const png = c.stbi_write_png_to_mem(slide_mem, state.window.viewport_size_x * @as(c_int, channels), state.window.viewport_size_x, state.window.viewport_size_y, channels, &png_len);
        assert(@intFromPtr(png) != 0);
        defer state.allocator.free(png[0..@intCast(png_len)]);
        assert(c.pdf_add_image_data(pdf, null, 0, 0, pdf_width, pdf_height, png, @intCast(png_len)) >= 0);
    }

    assert(c.pdf_save(pdf, @ptrCast(pdf_file_name.items)) >= 0);
    print("Dumped slide show to PDF file: '{s}'.\n", .{ pdf_file_name.items });
    c.pdf_destroy(pdf);

    // load the original state
    c.glfwSetWindowSize(state.window.glfw_window, old_window_width, old_window_height);
    state.window.setFullscreen(old_fullscreen);
    state.slide_show.slide_index = current_slide_idx;
}
