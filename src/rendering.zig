const c = @import("c.zig");
const data = @import("data.zig");
const std = @import("std");
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const win = @import("window.zig");
const SlideShow = @import("slides.zig").SlideShow;
const zlm = @import("linalg.zig");

fn clearScreen(color: data.Color32) void {
    const float_color = color.toVec4();
    c.glClearColor(float_color.x, float_color.y, float_color.z, float_color.w);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
}

fn compileShader(src: [*:0]const c.GLchar, ty: c.GLenum) c.GLuint {
    const shader = c.glCreateShader(ty);
    c.glShaderSource(shader, 1, &src, null);
    c.glCompileShader(shader);

    var status = c.GL_FALSE;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);

    if (status != c.GL_TRUE) {
        var len: c.GLint = 0;
        c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &len);
        var alloc = std.heap.GeneralPurposeAllocator(.{}).init;
        const buf = alloc.allocator().allocSentinel(c.GLchar, @as(usize, @intCast(len)) * @sizeOf(c.GLchar) + 1, 0) catch @panic("error allocating buffer");
        defer std.heap.page_allcator.free(buf);
        c.glGetShaderInfoLog(shader, len, null, buf);
        @panic(buf);
    }
    return shader;
}

fn linkProgram(vs: c.GLuint, fs: c.GLuint) c.GLuint {
    const program = c.glCreateProgram();
    c.glAttachShader(program, vs);
    c.glAttachShader(program, fs);
    c.glLinkProgram(program);

    c.glDetachShader(program, fs);
    c.glDetachShader(program, vs);
    c.glDeleteShader(fs);
    c.glDeleteShader(vs);

    var status = c.GL_FALSE;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &status);

    if (status != c.GL_TRUE) {
        var len: c.GLint = 0;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &len);
        var alloc = std.heap.GeneralPurposeAllocator(.{}).init;
        const buf = alloc.allocator().allocSentinel(c.GLchar, @as(usize, @intCast(len)) * @sizeOf(c.GLchar) + 1, 0) catch @panic("error allocating buffer");
        defer std.heap.page_allcator.free(buf);
        c.glGetProgramInfoLog(program, len, null, buf);
        @panic(buf);
    }
    return program;
}

fn createShader(vert: [*:0]const c.GLchar, frag: [*:0]const c.GLchar) c.GLuint {
    const vs = compileShader(vert, c.GL_VERTEX_SHADER);
    const fs = compileShader(frag, c.GL_FRAGMENT_SHADER);
    const id = linkProgram(vs, fs);
    c.glBindFragDataLocation(id, 0, "out_color");
    return id;
}

fn generateTexture(mem: [*:0]const u8, width: c.GLint, height: c.GLint) c.GLuint {
    var tex_id: c.GLuint = 0;
    c.glGenTextures(1, &tex_id);
    c.glBindTexture(c.GL_TEXTURE_2D, tex_id);
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA8,
        width,
        height,
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        mem
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);

    return tex_id;
}

fn generateWhiteTexture() c.GLuint {
    var white_texture: c.GLuint = 0;
    c.glGenTextures(1, &white_texture);
    c.glBindTexture(c.GL_TEXTURE_2D, white_texture);
    const white_color_data = [4]u8{ 255, 255, 255, 255 };
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA8,
        1,
        1,
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        &white_color_data
    );
    return white_texture;
}

const Vertex = extern struct {
    position: zlm.Vec3,
    color: zlm.Vec4,
    uv: zlm.Vec2,
    tex_idx: c.GLfloat,
};

const FontStorage = extern struct {
    texture: c.GLuint = undefined,
    baked_chars: [data.glyph_count]c.stbtt_bakedchar = undefined,

    const Self = @This();

    fn init(allocator: Allocator, font_size: usize, buffer_side_size: usize) Self {
        var self: Self = .{};

        const size = buffer_side_size;
        const buffer = allocator.alloc(u8, size * size) catch @panic("allocation error");
        defer allocator.free(buffer);
        _ = c.stbtt_BakeFontBitmap(data.default_font, 0, @floatFromInt(font_size), @ptrCast(buffer), @intCast(size), @intCast(size), data.first_char, data.glyph_count, &self.baked_chars);

        c.glGenTextures(1, &self.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RED, @intCast(size), @intCast(size), 0, c.GL_RED, c.GL_UNSIGNED_BYTE, @ptrCast(buffer));
        c.glGenerateMipmap(c.GL_TEXTURE_2D);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);

        return self;
    }

    fn deinit(self: Self) void {
        c.glDeleteTextures(1, &self.texture);
    }
};

const builtin_font_size_count: usize = 7;
const baked_font_sizes = [builtin_font_size_count]usize{ 12, 16, 24, 32, 48, 64, 96 }; // indices correspond to indices in a texture array

/// converts a font size to an index in the font texture array, when in doubt the bigger size is chosen
fn fontSizeIndex(font_size: usize) usize {
    for (baked_font_sizes, 0..) |size, i|  {
        const dist: i64 = @as(i64, @intCast(font_size)) - @as(i64, @intCast(size));
        if (dist <= 0) return i;
    }
    return builtin_font_size_count - 1;
}

const FontData = struct {
    font_info: c.stbtt_fontinfo = undefined,
    ascent: c_int = undefined,
    descent: c_int = undefined,
    line_gap: c_int = undefined,
    font_texture_side_pixel_size: usize = undefined,
    baked_fonts: [builtin_font_size_count]FontStorage = undefined,
    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator) Self {
        var self = Self{ .allocator = allocator };

        std.debug.assert(c.stbtt_InitFont(&self.font_info, data.default_font, 0) != 0);
        c.stbtt_GetFontVMetrics(&self.font_info, &self.ascent, &self.descent, &self.line_gap);
        var x0: c_int = undefined;
        var y0: c_int = undefined;
        var x1: c_int = undefined;
        var y1: c_int = undefined;
        c.stbtt_GetFontBoundingBox(&self.font_info, &x0, &y0 , &x1, &y1);
        const x_diff: usize = @intCast(@abs(x1 - x0));
        const y_diff: usize = @intCast(@abs(y1 - y0));
        const max_pixel_size: f32 = @floatFromInt(baked_font_sizes[baked_font_sizes.len - 1]);
        self.font_texture_side_pixel_size = @as(usize, @intFromFloat(@as(f32, @floatFromInt(@max(x_diff, y_diff))) * c.stbtt_ScaleForPixelHeight(&self.font_info, max_pixel_size) * @sqrt(@as(f32, @floatFromInt(data.glyph_count)))));

        for (0..builtin_font_size_count) |i| {
            self.baked_fonts[i] = FontStorage.init(self.allocator, baked_font_sizes[i], self.font_texture_side_pixel_size);
        }

        return self;
    }

    fn deinit(self: *Self) void {
        for (&self.baked_fonts) |*storage| {
            storage.deinit();
        }
    }
};

pub const Renderer = struct {
    shader: c.GLuint,
    white_texture: c.GLuint,
    vao: c.GLuint = 0,
    vbo: c.GLuint = 0,
    ibo: c.GLuint = 0,
    index_count: c.GLsizei = 0,
    obj_buffer: ArrayList(Vertex),
    all_tex_ids: ArrayList(c.GLuint),
    max_num_meshes: usize = 100,
    projection: zlm.Mat4 = zlm.Mat4.ortho(-win.viewport_ratio, win.viewport_ratio, -1.0, 1.0, 0.1, 2.0),
    view: zlm.Mat4 = zlm.Mat4.lookAt(zlm.Vec3.unitZ, zlm.Vec3.zero, zlm.Vec3.unitY),
    textures: StringHashMap(c.GLuint),
    font_data: FontData,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var self = Self{
            .shader = createShader(data.vertex_shader, data.fragment_shader),
            .white_texture = generateWhiteTexture(),
            .obj_buffer = ArrayList(Vertex).init(allocator),
            .all_tex_ids = ArrayList(c.GLuint).init(allocator),
            .textures = StringHashMap(c.GLuint).init(allocator),
            .font_data = FontData.init(allocator),
        };

        c.glGenVertexArrays(1, &self.vao);
        c.glBindVertexArray(self.vao);
        c.glGenBuffers(1, &self.vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(data.plane_vertices.len * self.max_num_meshes * @sizeOf(Vertex)),
            null,
            c.GL_DYNAMIC_DRAW
        );
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "position")));
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(1, 4, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "color")));
        c.glEnableVertexAttribArray(2);
        c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "uv")));
        c.glEnableVertexAttribArray(3);
        c.glVertexAttribPointer(3, 1, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "tex_idx")));

        const num_indices = data.plane_indices.len * self.max_num_meshes;
        var indices = try ArrayList(c.GLuint).initCapacity(allocator, num_indices);
        defer indices.deinit();

        for (0..num_indices) |i| {
            indices.appendAssumeCapacity(@intCast(data.plane_indices[i % data.plane_indices.len] + data.plane_vertices.len * (i / data.plane_indices.len)));
        }

        c.glGenBuffers(1, &self.ibo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        c.glBufferData(
            c.GL_ELEMENT_ARRAY_BUFFER,
            @intCast(data.plane_indices.len * self.max_num_meshes * @sizeOf(c.GLuint)),
            @ptrCast(indices.items),
            c.GL_STATIC_DRAW
        );
        c.glBindVertexArray(0);

        return self;
    }

    pub fn deinit(self: *Self) void {
        c.glDeleteProgram(self.shader);
        c.glDeleteTextures(1, &self.white_texture);
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteBuffers(1, &self.ibo);
        c.glDeleteVertexArrays(1, &self.vao);

        self.obj_buffer.deinit();
        self.all_tex_ids.deinit();

        var iterator = self.textures.valueIterator();
        while (iterator.next()) |tex_id| {
            c.glDeleteTextures(1, tex_id);
        }
        self.textures.deinit();
        self.font_data.deinit();
    }

    pub fn loadSlideData(self: *Self, slide_show: *SlideShow) void {
        for (slide_show.slides.items) |*slide| {
            for (slide.sections.items) |*section| {
                if (section.section_type != .image) continue;
                if (self.textures.contains(section.data.text.items)) continue;

                var width: c_int = undefined;
                var height: c_int = undefined;
                var num_channels: c_int = undefined;
                const image_data = c.stbi_load(@ptrCast(section.data.text.items), &width, &height, &num_channels, 4);
                if (num_channels != 4) {
                    @panic("Image source does not have RGBA channels.");
                }

                const tex_id = generateTexture(image_data, width, height);
                c.stbi_image_free(image_data);
                self.textures.put(section.data.text.items, tex_id) catch @panic("error inserting texture");
            }
        }
    }

    pub fn render(self: *Self, slide_show: *SlideShow) !void {
        const current_slide = slide_show.currentSlide();
        if (current_slide == null) {
            clearScreen(data.clear_color);
            return;
        }
        const slide = current_slide.?;
        clearScreen(slide.background_color);

        const line_spacing: f32 = 2.0; // will be set in the slide files in the future
        const yadvance: f32 = @as(f32, @floatFromInt(self.font_data.ascent - self.font_data.descent + self.font_data.line_gap)) + line_spacing;
        var cursor_x: f32 = 0; // x position in font metric units
        var cursor_y: f32 = 0; // y baseline position in font metric units

        for (slide.sections.items) |*section| {
            const window_scale_factor = @as(f32, @floatFromInt(section.text_size)) / @as(f32, @floatFromInt(data.viewport_resolution_reference[1]));

            switch (section.section_type) {
                .space => {
                    cursor_y += yadvance * @as(f32, @floatFromInt(section.data.lines));
                },
                .text => {
                    const used_font_size_index = fontSizeIndex(section.text_size);
                    const used_font_size = baked_font_sizes[used_font_size_index];
                    const font_storage = self.font_data.baked_fonts[used_font_size_index];

                    const font_scale = window_scale_factor * @as(f32, @floatFromInt(used_font_size)) / @as(f32, @floatFromInt(self.font_data.ascent - self.font_data.descent));
                    const scale = zlm.Mat4.scaleFromFactor(font_scale);

                    const tex_id: c.GLuint = font_storage.texture;

                    for (section.data.text.items) |char| {
                        const baked_char = &font_storage.baked_chars[@as(usize, @intCast(char)) - data.first_char];

                        switch (char) {
                            '\n' => {
                                cursor_y += yadvance;
                                cursor_x = 0;
                            },
                            ' ' => {
                                cursor_x += baked_char.xadvance;
                            },
                            else => {
                                const x_pos = cursor_x + baked_char.xoff + @as(f32, @floatFromInt(baked_char.x1 - baked_char.x0)) / 2.0;
                                const y_pos = cursor_y + baked_char.yoff + @as(f32, @floatFromInt(baked_char.y1 - baked_char.y0)) / 2.0;
                                const position = zlm.vec3(x_pos, y_pos, 1.0); // the z coord might change in the future with support for layers
                                const trafo = zlm.Mat4.translation(position).mul(scale);

                                const font_texture_side_pixel_size: f32 = @floatFromInt(self.font_data.font_texture_side_pixel_size);
                                const u_coord_0 = @as(f32, @floatFromInt(baked_char.x0)) / font_texture_side_pixel_size;
                                const v_coord_0 = @as(f32, @floatFromInt(baked_char.y0)) / font_texture_side_pixel_size;
                                const u_coord_1 = @as(f32, @floatFromInt(baked_char.x1)) / font_texture_side_pixel_size;
                                const v_coord_1 = @as(f32, @floatFromInt(baked_char.y1)) / font_texture_side_pixel_size;
                                const uv_scale = zlm.vec2(u_coord_1 - u_coord_0, v_coord_1 - v_coord_0);
                                const uv_offset = zlm.vec2(u_coord_0, v_coord_0);

                                _ = self.addTexQuad(trafo, tex_id, uv_scale, uv_offset); // TODO: return value
                                cursor_x += baked_char.xadvance;
                            },
                        }
                    }
                    cursor_y += yadvance;
                },
                .image => {
                    const image_scale = zlm.Mat4.scaleFromFactor(window_scale_factor);
                    const position = zlm.vec3(0.0, 0.0, 1.0); // the z coord might change in the future with support for layers
                    const trafo = zlm.Mat4.translation(position).mul(image_scale);
                    const tex_id = self.textures.get(section.data.text.items).?;
                    _ = self.addTexQuad(trafo, tex_id, zlm.Vec2.one, zlm.Vec2.zero); // TODO: return value
                    cursor_y += yadvance;
                },
            }
        }

        self.flush();
    }

    fn flush(self: *Self) void {
        c.glUseProgram(self.shader);

        // copy the data to the GPU
        const vertices_size = self.obj_buffer.items.len * @sizeOf(Vertex);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferSubData(
            c.GL_ARRAY_BUFFER,
            0,
            @intCast(vertices_size),
            @ptrCast(self.obj_buffer.items)
        );

        // bind uniforms
        c.glUniformMatrix4fv(0, 1, c.GL_FALSE, &self.projection.fields[0][0]);
        c.glUniformMatrix4fv(4, 1, c.GL_FALSE, &self.view.fields[0][0]);
        for (0..max_texture_count) |i| {
            c.glUniform1i(@intCast(8 + i), @intCast(i));
        }
        // bind texture
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.white_texture);

        // bind textures
        for (self.all_tex_ids.items, 0..) |tex_id, i| {
            const unit: c.GLenum = @intCast(i);
            const base_unit: c.GLenum = @as(c.GLenum, @intCast(c.GL_TEXTURE1)); // ??? wtf
            c.glActiveTexture(base_unit + unit);
            c.glBindTexture(c.GL_TEXTURE_2D, tex_id);
        }
        // draw the triangles corresponding to the index buffer
        c.glBindVertexArray(self.vao);
        c.glDrawElements(
            c.GL_TRIANGLES,
            self.index_count,
            c.GL_UNSIGNED_INT,
            null
        );
        c.glBindVertexArray(0);

        self.index_count = 0;
        self.obj_buffer.clearRetainingCapacity();
    }

    fn addTexQuad(self: *Self, trafo: zlm.Mat4, tex_id: c.GLuint, uv_scale: zlm.Vec2, uv_offset: zlm.Vec2) bool {
        // determine texture index
        var tex_idx: c.GLfloat = -1.0;
        for (0..self.all_tex_ids.items.len) |i| {
            const id = self.all_tex_ids.items[i];
            if (id == tex_id) {
                tex_idx = @floatFromInt(i + 1);
                break;
            }
        }
        if (tex_idx == -1.0) {
            if (self.all_tex_ids.items.len >= max_texture_count - 1) {
                // start a new batch if out of texture slots
                return false;
            }
            tex_idx = @floatFromInt(self.all_tex_ids.items.len + 1);
            self.all_tex_ids.append(tex_id) catch @panic("allocation error");
        }
        if (self.index_count >= data.plane_indices.len * self.max_num_meshes) {
            return false;
        }
        // copy mesh vertex data into the object buffer
        for (0..data.plane_vertices.len) |i| {
            self.obj_buffer.append(.{
                .position = data.plane_vertices[i].transform4(trafo),
                .color = zlm.Vec4.fromElement(1.0),
                .uv = data.plane_uvs[i].mul(uv_scale).add(uv_offset),
                .tex_idx = tex_idx,
            }) catch @panic("allocation error");
        }
        self.index_count += data.plane_indices.len;
        return true;
    }

    fn addColorQuad(self: Self, trafo: zlm.Mat4, color: data.Color32) bool {
        if (self.index_count >= data.plane_indices.len * self.max_num_meshes) {
            return false;
        }
        // copy mesh vertex data into the object buffer
        for (0..data.plane_vertices.len) |i| {
            self.obj_buffer.append(.{
                .position = data.plane_vertices[i].transform4(trafo),
                .color = color.toVec4(),
                .uv = data.plane_uvs[i],
                .tex_idx = 0.0, // white texture
            }) catch @panic("allocation error");
        }
        self.index_count += data.plane_indices.len;
        return true;
    }
};

const max_texture_count: usize = 32;
