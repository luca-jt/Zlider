const std = @import("std");
const SlideShow = @import("slides.zig").SlideShow;
const Renderer = @import("rendering.zig").Renderer;

pub var renderer: Renderer = undefined;
pub var slide_show: SlideShow = undefined;

const WindowState = extern struct {
    win_pos_x: i32 = 0,
    win_pos_y: i32 = 0,
    win_size_x: i32 = 0,
    win_size_y: i32 = 0,
    vp_pos_x: i32 = 0,
    vp_pos_y: i32 = 0,
    vp_size_x: i32 = 0,
    vp_size_y: i32 = 0,
};
pub var window_state: WindowState = .{};
