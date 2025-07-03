const c = @import("c.zig");
const data = @import("data.zig");
const std = @import("std");
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const win = @import("window.zig");
const SlideShow = @import("slides.zig").SlideShow;
const lina = @import("linalg.zig");

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
        const allocator = std.heap.c_allocator;
        const buf = allocator.allocSentinel(c.GLchar, @as(usize, @intCast(len)) * @sizeOf(c.GLchar) + 1, 0) catch @panic("allocation error");
        defer allocator.free(buf);
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
        const allocator = std.heap.c_allocator;
        const buf = allocator.allocSentinel(c.GLchar, @as(usize, @intCast(len)) * @sizeOf(c.GLchar) + 1, 0) catch @panic("allocation error");
        defer allocator.free(buf);
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
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
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
    position: lina.Vec3,
    color: lina.Vec4,
    uv: lina.Vec2,
    tex_idx: c.GLfloat,
};

const font_texture_swizzle_mask = [4:0]c.GLint{ c.GL_ONE, c.GL_ONE, c.GL_ONE, c.GL_RED };

const FontStorage = extern struct {
    texture: c.GLuint = undefined,
    baked_chars: [data.glyph_count]c.stbtt_bakedchar = undefined,

    const Self = @This();

    fn initWithFontData(allocator: Allocator, font_size: usize, buffer_side_size: usize) !Self {
        var self: Self = .{};

        const size = buffer_side_size;
        const buffer = try allocator.alloc(u8, size * size);
        defer allocator.free(buffer);
        _ = c.stbtt_BakeFontBitmap(data.default_font, 0, @floatFromInt(font_size), @ptrCast(buffer), @intCast(size), @intCast(size), data.first_char, data.glyph_count, &self.baked_chars);

        c.glGenTextures(1, &self.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R8, @intCast(size), @intCast(size), 0, c.GL_RED, c.GL_UNSIGNED_BYTE, @ptrCast(buffer));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteriv(c.GL_TEXTURE_2D, c.GL_TEXTURE_SWIZZLE_RGBA, &font_texture_swizzle_mask);

        return self;
    }
};

const builtin_font_size_count: usize = 6;
const baked_font_sizes = [builtin_font_size_count]usize{ 16, 32, 64, 128, 160, 192 }; // indices correspond to indices in a texture array

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

    fn init(allocator: Allocator) !Self {
        var self = Self{ .allocator = allocator };

        std.debug.assert(c.stbtt_InitFont(&self.font_info, data.default_font, 0) != 0);
        c.stbtt_GetFontVMetrics(&self.font_info, &self.ascent, &self.descent, &self.line_gap);

        const max_pixel_size: f32 = @floatFromInt(baked_font_sizes[baked_font_sizes.len - 1]);
        self.font_texture_side_pixel_size = @intFromFloat(max_pixel_size * @ceil(@sqrt(@as(f32, @floatFromInt(data.glyph_count)))));

        for (0..builtin_font_size_count) |i| {
            self.baked_fonts[i] = try FontStorage.initWithFontData(self.allocator, baked_font_sizes[i], self.font_texture_side_pixel_size);
            // for now all the font textures have the same size because its easier and does not really matter
        }
        return self;
    }

    fn deinit(self: *Self) void {
        for (&self.baked_fonts) |*storage| {
            c.glDeleteTextures(1, &storage.texture);
        }
    }
};

const ImageData = struct {
    texture: c.GLuint,
    width: usize,
    height: usize,
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
    max_num_meshes: usize,
    projection: lina.Mat4 = lina.Mat4.ortho(-win.viewport_ratio / 2, win.viewport_ratio / 2, -0.5, 0.5, 0.1, 2.0),
    view: lina.Mat4 = lina.Mat4.lookAt(lina.vec3(0.5 * win.viewport_ratio, -0.5, 1.0), lina.vec3(0.5 * win.viewport_ratio, -0.5, 0.0), lina.Vec3.unitY),
    images: StringHashMap(ImageData),
    font_data: FontData,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        c.glEnable(c.GL_SCISSOR_TEST);
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glEnable(c.GL_DEPTH_TEST);
        c.glDepthFunc(c.GL_LESS);
        c.glDisable(c.GL_MULTISAMPLE);
        c.glDisable(c.GL_FRAMEBUFFER_SRGB);

        const max_num_meshes: usize = 200;
        var self = Self{
            .shader = createShader(data.vertex_shader, data.fragment_shader),
            .white_texture = generateWhiteTexture(),
            .obj_buffer = try ArrayList(Vertex).initCapacity(allocator, max_num_meshes * data.plane_vertices.len),
            .all_tex_ids = try ArrayList(c.GLuint).initCapacity(allocator, max_texture_count - 1),
            .max_num_meshes = max_num_meshes,
            .images = StringHashMap(ImageData).init(allocator),
            .font_data = try FontData.init(allocator),
            .allocator = allocator,
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

        var iterator = self.images.valueIterator();
        while (iterator.next()) |image_data| {
            c.glDeleteTextures(1, &image_data.texture);
        }
        self.images.deinit();
        self.font_data.deinit();
    }

    pub fn clear(self: *Self) void {
        self.obj_buffer.clearRetainingCapacity();
        var iterator = self.images.valueIterator();
        while (iterator.next()) |image_data| {
            c.glDeleteTextures(1, &image_data.texture);
        }
        self.images.clearRetainingCapacity();
    }

    pub fn loadSlideData(self: *Self, slide_show: *SlideShow) void {
        for (slide_show.slides.items) |*slide| {
            for (slide.sections.items) |*section| {
                if (section.section_type != .image) continue;
                if (self.images.contains(section.data.text.items)) continue;

                var width: c_int = undefined;
                var height: c_int = undefined;
                var num_channels: c_int = undefined;
                const image = c.stbi_load(@ptrCast(section.data.text.items), &width, &height, &num_channels, 4);

                const tex_id = generateTexture(image, width, height);
                c.stbi_image_free(image);
                const image_data: ImageData = .{ .texture = tex_id, .width = @intCast(width), .height = @intCast(height) };
                self.images.put(section.data.text.items, image_data) catch @panic("allocation error");
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

        const min_x_start: f64 = 10; // in pixels
        const line_height: f64 = @floatFromInt(self.font_data.ascent - self.font_data.descent);

        var cursor_x: f64 = min_x_start; // x position in pixel units
        var cursor_y: f64 = 0; // y baseline position in pixel units

        for (slide.sections.items) |*section| {
            const sourced_font_size_index = fontSizeIndex(section.text_size * 2); // this ensures crisp fonts on large screens
            const sourced_font_size: f64 = @floatFromInt(baked_font_sizes[sourced_font_size_index]);
            const font_display_scale: f64 = @as(f64, @floatFromInt(section.text_size)) / sourced_font_size; // we are not sourcing the font size that is displayed
            const inverse_viewport_height = 1.0 / @as(f64, @floatFromInt(data.viewport_resolution_reference[1])); // y-axis as scale reference
            const font_scale = sourced_font_size / line_height;

            const yadvance_font: f64 = -(line_height + @as(f64, @floatFromInt(self.font_data.line_gap))) * section.line_spacing; // in font units (analogous to the xadvance in font data but generic)
            const yadvance = yadvance_font * font_scale * font_display_scale; // this is the specific yadvance accounting for font sizes

            switch (section.section_type) {
                .space => {
                    cursor_y += yadvance * @as(f64, @floatFromInt(section.data.lines));
                },
                .text => {
                    const font_storage = self.font_data.baked_fonts[sourced_font_size_index];
                    const tex_id: c.GLuint = font_storage.texture;
                    var line_iterator = data.LineIterator.fromSlice(section.data.text.items);

                    while (line_iterator.next()) |line| {
                        var line_width: f64 = 0;
                        for (line) |char| {
                            const baked_char = &font_storage.baked_chars[@as(usize, @intCast(char)) - data.first_char];
                            line_width += baked_char.xadvance * font_display_scale;
                        }
                        cursor_x = switch (section.alignment) {
                            .center => (data.viewport_resolution_reference[0] - line_width) / 2,
                            .right => data.viewport_resolution_reference[0] - line_width - min_x_start,
                            .left => min_x_start,
                        };

                        for (line) |char| {
                            const baked_char = &font_storage.baked_chars[@as(usize, @intCast(char)) - data.first_char];
                            // lines don't contain the trailing new-line character
                            switch (char) {
                                ' ' => {
                                    cursor_x += baked_char.xadvance * font_display_scale;
                                },
                                else => {
                                    const x_pos = (cursor_x + baked_char.xoff * font_display_scale) * inverse_viewport_height;
                                    const y_pos = (cursor_y - line_height * font_scale * font_display_scale - baked_char.yoff * font_display_scale) * inverse_viewport_height; // the switch of the sign of the y-offset is done to keep the way projections are done

                                    const position = lina.vec3(@floatCast(x_pos), @floatCast(y_pos), 0.0); // the z coord might change in the future with support for layers

                                    const scale = lina.Mat4.scale(.{ .x = @as(f32, @floatFromInt(baked_char.x1 - baked_char.x0)) / @as(f32, @floatFromInt(baked_char.y1 - baked_char.y0)), .y = 1.0, .z = 1.0, }); // the baked char data used does not require scaling because it would just cancel out
                                    const pixel_scale = lina.Mat4.scaleFromFactor(@floatCast(inverse_viewport_height * @as(f64, @floatFromInt(baked_char.y1 - baked_char.y0)) * font_display_scale));
                                    const trafo = lina.Mat4.translation(position).mul(scale).mul(pixel_scale);

                                    const font_texture_side_pixel_size: f32 = @floatFromInt(self.font_data.font_texture_side_pixel_size);
                                    const u_0 = @as(f32, @floatFromInt(baked_char.x0)) / font_texture_side_pixel_size;
                                    const v_0 = @as(f32, @floatFromInt(baked_char.y0)) / font_texture_side_pixel_size;
                                    const u_1 = @as(f32, @floatFromInt(baked_char.x1)) / font_texture_side_pixel_size;
                                    const v_1 = @as(f32, @floatFromInt(baked_char.y1)) / font_texture_side_pixel_size;
                                    const uvs = [data.plane_uvs.len]lina.Vec2{ lina.vec2(u_0, v_1), lina.vec2(u_1, v_0), lina.vec2(u_0, v_0), lina.vec2(u_1, v_1) };

                                    if (!try self.addFontQuad(trafo, tex_id, &uvs, section.text_color)) {
                                        self.flush();
                                        std.debug.assert(try self.addFontQuad(trafo, tex_id, &uvs, section.text_color));
                                    }
                                    cursor_x += baked_char.xadvance * font_display_scale;
                                },
                            }
                        }
                        cursor_y += yadvance;
                    }
                    cursor_y += yadvance;
                },
                .image => {
                    const image_data = self.images.get(section.data.text.items).?;
                    cursor_x = switch (section.alignment) {
                        .center => (data.viewport_resolution_reference[0] - @as(f64, @floatFromInt(image_data.width)) * section.image_scale) / 2,
                        .right => data.viewport_resolution_reference[0] - @as(f64, @floatFromInt(image_data.width)) * section.image_scale - min_x_start,
                        .left => min_x_start,
                    };

                    const x_pos = cursor_x * inverse_viewport_height;
                    const y_pos = cursor_y * inverse_viewport_height;
                    const position = lina.vec3(@floatCast(x_pos), @floatCast(y_pos), 0.0); // the z coord might change in the future with support for layers

                    const image_scale = lina.Mat4.scaleFromFactor(section.image_scale);
                    const scale = lina.Mat4.scale(.{ .x = @as(f32, @floatFromInt(image_data.width)) / @as(f32, @floatFromInt(image_data.height)), .y = 1.0, .z = 1.0, });
                    const pixel_scale = lina.Mat4.scaleFromFactor(@as(f32, @floatCast(inverse_viewport_height)) * @as(f32, @floatFromInt(image_data.height)));
                    const trafo = lina.Mat4.translation(position).mul(scale).mul(pixel_scale).mul(image_scale);

                    if (!try self.addImageQuad(trafo, image_data.texture)) {
                        self.flush();
                        std.debug.assert(try self.addImageQuad(trafo, image_data.texture));
                    }
                    cursor_y -= @as(f64, @floatFromInt(image_data.height));
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
        const base_unit: c.GLenum = @as(c.GLenum, @intCast(c.GL_TEXTURE1)); // ??? wtf
        for (self.all_tex_ids.items, 0..) |tex_id, i| {
            const unit: c.GLenum = @intCast(i);
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

    fn addFontQuad(self: *Self, trafo: lina.Mat4, tex_id: c.GLuint, uvs: []const lina.Vec2, color: data.Color32) !bool {
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
            self.all_tex_ids.appendAssumeCapacity(tex_id);
        }
        if (self.index_count >= data.plane_indices.len * self.max_num_meshes) {
            // resize batch if size is exceeded
            try self.resizeBuffer();
        }
        // copy mesh vertex data into the object buffer
        for (0..data.plane_vertices.len) |i| {
            self.obj_buffer.appendAssumeCapacity(.{
                .position = data.plane_vertices[i].transform4(trafo),
                .color = color.toVec4(),
                .uv = uvs[i],
                .tex_idx = tex_idx,
            });
        }
        self.index_count += data.plane_indices.len;
        return true;
    }

    fn addImageQuad(self: *Self, trafo: lina.Mat4, tex_id: c.GLuint) !bool {
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
            self.all_tex_ids.appendAssumeCapacity(tex_id);
        }
        if (self.index_count >= data.plane_indices.len * self.max_num_meshes) {
            // resize batch if size is exceeded
            try self.resizeBuffer();
        }
        // copy mesh vertex data into the object buffer
        for (0..data.plane_vertices.len) |i| {
            self.obj_buffer.appendAssumeCapacity(.{
                .position = data.plane_vertices[i].transform4(trafo),
                .color = lina.Vec4.fromElement(1.0),
                .uv = data.plane_uvs[i],
                .tex_idx = tex_idx,
            });
        }
        self.index_count += data.plane_indices.len;
        return true;
    }

    fn addColorQuad(self: Self, trafo: lina.Mat4, color: data.Color32) !void {
        if (self.index_count >= data.plane_indices.len * self.max_num_meshes) {
            // resize batch if size is exceeded
            try self.resizeBuffer();
        }
        // copy mesh vertex data into the object buffer
        for (0..data.plane_vertices.len) |i| {
            self.obj_buffer.appendAssumeCapacity(.{
                .position = data.plane_vertices[i].transform4(trafo),
                .color = color.toVec4(),
                .uv = data.plane_uvs[i],
                .tex_idx = 0.0, // white texture
            });
        }
        self.index_count += data.plane_indices.len;
    }

    fn resizeBuffer(self: *Self) !void {
        self.max_num_meshes *= 2;
        try self.obj_buffer.ensureTotalCapacity(self.max_num_meshes);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(data.plane_vertices.len * self.max_num_meshes * @sizeOf(Vertex)),
            null,
            c.GL_DYNAMIC_DRAW
        );

        const num_indices = data.plane_indices.len * self.max_num_meshes;
        var indices = try ArrayList(c.GLuint).initCapacity(self.allocator, num_indices);
        defer indices.deinit();

        for (0..num_indices) |i| {
            indices.appendAssumeCapacity(@intCast(data.plane_indices[i % data.plane_indices.len] + data.plane_vertices.len * (i / data.plane_indices.len)));
        }

        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        c.glBufferData(
            c.GL_ELEMENT_ARRAY_BUFFER,
            @intCast(data.plane_indices.len * self.max_num_meshes * @sizeOf(c.GLuint)),
            @ptrCast(indices.items),
            c.GL_STATIC_DRAW
        );
    }
};

const max_texture_count: usize = 32;
