const std = @import("std");
pub const ArrayList = std.ArrayList;
pub const String = std.ArrayList(u8);
const c = @import("c.zig");
const linalg = @import("linalg.zig");

pub const Color32 = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    pub fn to_vec4(self: Color32) linalg.Vec4 {
        const r = @as(f32, self.r) / 255.0;
        const g = @as(f32, self.g) / 255.0;
        const b = @as(f32, self.b) / 255.0;
        const a = @as(f32, self.a) / 255.0;
        return .{ r, g, b, a };
    }
};

//pub fn rgba_from_hex(hex: [:0]const u8) Color32 { // is the input type correct?
//    u32 number = (uint32_t)strtoul(hex, NULL, 16);
//    u8 r = (number & 0xFF000000) >> 24;
//    u8 g = (number & 0x00FF0000) >> 16;
//    u8 b = (number & 0x0000FF00) >> 8;
//    u8 a = number & 0x000000FF;
//    return .{ r, g, b, a };
//}

pub const SectionData = union {
    lines: usize,
    text: [:0]const u8,
};

pub const SectionType = enum { space, text, image };

pub const ElementAlignment = enum { center, right, left };

pub const Section = struct {
    text_size: usize,
    section_type: SectionType,
    data: SectionData,
    text_color: Color32,
    alignment: ElementAlignment
};

pub const Slide = struct {
    background_color: Color32,
    sections: ArrayList(Section)
};

pub const SlideShow = struct {
    slides: ArrayList(Slide),
    slide_index: usize = 0,
    title: [:0]const u8,

    const Self = @This();

    pub fn current_slide(self: *Self) *Slide {
        const slide = &(self.*.slides.items[self.*.slide_index]);
        return slide;
    }
};

pub const Keyword = enum(usize) {
    text_color = 0,
    bg = 1,
    slide = 2,
    define = 3,
    centered = 4,
    left = 5,
    right = 6,
    text = 7,
    space = 8,
    text_size = 9,
    image = 10,
};

pub const reserved_names = [_][:0]const u8{ "text_color", "bg", "slide", "define", "centered", "left", "right", "text", "space", "text_size", "image" };

pub const Token = union(enum) {
    none,
    err,
    slide,
    centered,
    right,
    left,
    file: String,
    bg: Color32,
    space: usize,
    text_size: usize,
    text: String,
    define: String,
    text_color: Color32,
};

pub const vertex_shader =
    \\#version 330 core
    \\layout(location = 0) in vec3 position;
    \\layout(location = 1) in vec4 color;
    \\layout(location = 2) in vec2 uv\
    \\layout(location = 3) in float tex_idx;
    \\out vec4 v_color;
    \\out vec2 v_uv;
    \\flat out float v_tex_idx;
    \\layout(location = 0) uniform mat4 projection;
    \\layout(location = 4) uniform mat4 view;
    \\void main() {
    \\    gl_Position = projection * view * vec4(position, 1.0);
    \\    v_color = color;
    \\    v_uv = uv;
    \\    v_tex_idx = tex_idx;
    \\}
;

pub const fragment_shader =
    \\#version 330 core
    \\in vec4 v_color;
    \\in vec2 v_uv;
    \\flat in float v_tex_idx;
    \\out vec4 out_color;
    \\layout(location = 8) uniform sampler2D tex_sampler[32];
    \\void main() {
    \\    int sampler_idx = int(round(v_tex_idx));
    \\    vec4 textured = texture(tex_sampler[sampler_idx], v_uv).rgba;
    \\    if (textured.a < 0.001) {
    \\        discard;
    \\    }
    \\    out_color = textured * v_color;
    \\}
;

pub const plane_vertices = [4]linalg.Vec3{ .{ -0.5, -0.5, 0.0 }, .{ 0.5, 0.5, 0.0 }, .{ -0.5, 0.5, 0.0 }, .{ 0.5, -0.5, 0.0 } };
pub const plane_uvs = [4]linalg.Vec2{ .{ 0.0, 1.0 }, .{ 1.0, 0.0 }, .{ 0.0, 0.0 }, .{ 1.0, 1.0 } };
pub const plane_indices = [6]c.GLuint{ 0, 1, 2, 0, 3, 1 };
