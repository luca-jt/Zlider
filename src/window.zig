const target_os = @import("builtin").target.os.tag;
const c = @import("c.zig");

const WindowState = packed struct {
    win_pos_x: i32 = 0,
    win_pos_y: i32 = 0,
    win_size_x: i32 = 0,
    win_size_y: i32 = 0,
    vp_pos_x: i32 = 0,
    vp_pos_y: i32 = 0,
    vp_size_x: i32 = 0,
    vp_size_y: i32 = 0,
};
var window_state: WindowState = .{};

const viewport_ratio: f32 = 16.0 / 9.0;

pub fn update_window_attributes(window: *c.GLFWwindow) void {
    c.glfwGetWindowPos(window, &window_state.win_pos_x, &window_state.win_pos_y);
    c.glfwGetWindowSize(window, &window_state.win_size_x, &window_state.win_size_y);
}

fn resize_viewport(width: u32, height: u32) void {
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

pub fn init_window(width: u32, height: u32, title: [:0]const u8) *c.GLFWwindow {
    if (c.glfwInit() == c.GL_FALSE) {
        @panic("Failed to initialize GLFW.");
    }

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
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

    resize_viewport(width, height);

    return window;
}

pub fn close_window(window: *c.GLFWwindow) void {
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}

fn framebuffer_size_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    resize_viewport(@intCast(width), @intCast(height));
    c.glGetIntegerv(c.GL_VIEWPORT, &window_state.vp_pos_x); // this overwrites both viewport position and size
    c.glfwGetWindowSize(window, &window_state.win_size_x, &window_state.win_size_y);
}

fn window_pos_callback(window: ?*c.GLFWwindow, xpos: c_int, ypos: c_int) callconv(.c) void {
    _ = xpos; // to suppress errors
    _ = ypos;
    c.glfwGetWindowPos(window, &window_state.win_pos_x, &window_state.win_pos_y);
}

pub fn set_event_config(window: *c.GLFWwindow) void {
    c.glfwSetInputMode(window, c.GLFW_LOCK_KEY_MODS, c.GLFW_TRUE);
    c.glfwSetInputMode(window, c.GLFW_STICKY_KEYS, c.GLFW_TRUE);
    _ = c.glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
    _ = c.glfwSetWindowPosCallback(window, window_pos_callback);
}
