const std = @import("std");
pub const String = std.ArrayList(u8);
const c = @import("c.zig");
const lina = @import("linalg.zig");

pub const Color32 = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    const Self = @This();

    pub fn new(r: u8, g: u8, b: u8, a: u8) Self {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn toVec4(self: Color32) lina.Vec4 {
        const r = @as(f32, @floatFromInt(self.r)) / 255.0;
        const g = @as(f32, @floatFromInt(self.g)) / 255.0;
        const b = @as(f32, @floatFromInt(self.b)) / 255.0;
        const a = @as(f32, @floatFromInt(self.a)) / 255.0;
        return lina.vec4(r, g, b, a);
    }

    pub fn fromHex(hex: []const u8) ?Color32 {
        const number = std.fmt.parseInt(u32, hex, 16) catch return null;
        const r: u8 = @intCast((number & 0xFF000000) >> 24);
        const g: u8 = @intCast((number & 0x00FF0000) >> 16);
        const b: u8 = @intCast((number & 0x0000FF00) >> 8);
        const a: u8 = @intCast((number & 0x000000FF));
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
};

pub const clear_color = Color32.new(0, 0, 0, 255); // this can be adjusted if you want

pub const Keyword = enum(usize) {
    text_color = 0,
    bg = 1,
    slide = 2,
    centered = 3,
    left = 4,
    right = 5,
    text = 6,
    space = 7,
    text_size = 8,
    image = 9,
};

pub const reserved_names = [_][]const u8{ "text_color", "bg", "slide", "centered", "left", "right", "text", "space", "text_size", "image" };

pub const Token = union(enum) {
    text_color: Color32,
    bg: Color32,
    slide,
    centered,
    left,
    right,
    text: String,
    space: usize,
    text_size: usize,
    image: String,
};

pub const vertex_shader: [*:0]const u8 =
    \\#version 450 core
    \\
    \\layout(location = 0) in vec3 position;
    \\layout(location = 1) in vec4 color;
    \\layout(location = 2) in vec2 uv;
    \\layout(location = 3) in float tex_idx;
    \\
    \\out vec4 v_color;
    \\out vec2 v_uv;
    \\
    \\flat out float v_tex_idx;
    \\
    \\layout(location = 0) uniform mat4 projection;
    \\layout(location = 4) uniform mat4 view;
    \\
    \\void main() {
    \\    gl_Position = projection * view * vec4(position, 1.0);
    \\    v_color = color;
    \\    v_uv = uv;
    \\    v_tex_idx = tex_idx;
    \\}
;

pub const fragment_shader: [*:0]const u8 =
    \\#version 450 core
    \\
    \\in vec4 v_color;
    \\in vec2 v_uv;
    \\flat in float v_tex_idx;
    \\
    \\out vec4 out_color;
    \\
    \\layout(location = 8) uniform sampler2D tex_sampler[32];
    \\
    \\void main() {
    \\    int sampler_idx = int(round(v_tex_idx));
    \\    vec4 textured = texture(tex_sampler[sampler_idx], v_uv).rgba;
    \\    if (textured.a < 0.001) {
    \\        discard;
    \\    }
    \\    out_color = textured * v_color;
    \\}
;

pub const plane_vertices = [4]lina.Vec3{
    lina.vec3(0.0, -1.0, 0.0),
    lina.vec3(1.0, 0.0, 0.0),
    lina.vec3(0.0, 0.0, 0.0),
    lina.vec3(1.0, -1.0, 0.0)
};

pub const plane_uvs = [4]lina.Vec2{
    lina.vec2(0.0, 1.0),
    lina.vec2(1.0, 0.0),
    lina.vec2(0.0, 0.0),
    lina.vec2(1.0, 1.0)
};

pub const plane_indices = [6]c.GLuint{ 0, 1, 2, 0, 3, 1 };

pub const default_font: [:0]const u8 = @embedFile("fonts/DMSerifText-Regular.ttf");
pub const first_char: c_int = 32;
pub const glyph_count: c_int = 255 - first_char;

// this determines the scaling of the text in rendering, the font size relative to the window size should not change
pub const viewport_resolution_reference: struct { usize, usize } = .{ 1920, 1080 }; // @Cleanup: in the future, when the format of the slides can be changed, this needs to be updated as well
