const std = @import("std");
const String = std.ArrayList(u8);
const Allocator = std.mem.Allocator;
const c = @import("c.zig");
const lina = @import("linalg.zig");

/// Allocates memory, reads the contents of an entire file into a dynamic string and adds null-termination.
pub fn readEntireFile(file_name: []const u8, allocator: Allocator) !String {
    const dir = std.fs.cwd();
    const buffer = try dir.readFileAlloc(allocator, file_name, 4096);
    var string = String.fromOwnedSlice(allocator, buffer);
    try string.append(0); // do this for lexing pointer stuff
    errdefer string.deinit();
    return string;
}

pub const Color32 = packed struct {
    a: u8 = 0,
    b: u8 = 0,
    g: u8 = 0,
    r: u8 = 0,

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
        const number = std.fmt.parseInt(u32, hex, 0) catch return null;
        return @bitCast(number);
    }
};

pub const SplitIterator = struct {
    next_part_start: usize = 0,
    string: []const u8,
    delimiter: u8,
    include_empty_slices: bool = true,

    const Self = @This();

    pub fn next(self: *Self) ?[]const u8 {
        if (self.next_part_start > self.string.len) return null;
        const start = self.next_part_start;
        var end = start;

        for (self.string[start..]) |char| {
            if (char == self.delimiter) break;
            end += 1;
        }
        self.next_part_start = end + 1;

        const slice = self.string[start..end];
        if (slice.len == 0 and !self.include_empty_slices) return self.next();
        return slice;
    }

    pub fn peek(self: *Self, num: usize) ?[]const u8 {
        if (self.next_part_start > self.string.len or num == 0) return null;
        const start = self.next_part_start;
        var end = start;

        for (self.string[start..]) |char| {
            if (char == self.delimiter) break;
            end += 1;
        }

        var slice: ?[]const u8 = self.string[start..end];
        const slice_is_skipped = slice.?.len == 0 and !self.include_empty_slices;

        if (slice_is_skipped or num > 1) {
            self.next_part_start = end + 1;
            slice = self.peek(if (slice_is_skipped) num else num - 1);
            self.next_part_start = start;
        }
        return slice;
    }
};

pub fn extendStringToArrayZeroed(comptime len: usize, comptime slice: []const u8) [len]u8 {
    if (slice.len > len) @compileError("Cannot produce shorter array.");
    return (slice ++ [_]u8{0} ** (len - slice.len)).*;
}

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

pub const serif_font: [:0]const u8 = @embedFile("baked/DMSerifText-Regular.ttf");
pub const sans_serif_font: [:0]const u8 = @embedFile("baked/Roboto-Regular.ttf");
pub const monospace_font: [:0]const u8 = @embedFile("baked/SourceCodePro-Regular.ttf");
pub const first_char: c_int = 32;
pub const glyph_count: c_int = 255 - first_char;

pub const file_drop_image: [:0]const u8 = @embedFile("baked/file_drop.png");

pub const home_screen_slide: [:0]const u8 =
    \\center
    \\text_color 0xF6A319FF
    \\bg 0x2C2E34FF
    \\text_size 10
    \\image_scale 0.2
    \\
    \\space 6
    \\
    \\text_size 400
    \\
    \\text
    \\Zlider
    \\text
    \\
    \\text_color 0xE2E2E3FF
    \\text_size 30
    \\font monospace
    \\
    \\space 6
    \\
    \\text
    \\Drag and drop a slide show file to load.
    \\text
    \\
    \\space 2
    \\
    \\file_drop_image
;
