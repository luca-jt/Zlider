const Window = @import("window.zig").Window;
const SlideShow = @import("slides.zig").SlideShow;
const Renderer = @import("rendering.zig").Renderer;

pub var window: Window = .{};
pub var slide_show: SlideShow = undefined;
pub var renderer: Renderer = undefined;
