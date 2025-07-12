const c = @import("c.zig");
const data = @import("data.zig");
const std = @import("std");
const StringHashMap = std.StringHashMap;
const HashMap = std.AutoHashMap;
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

const font_render_size_multiplier: usize = 2; // picks a larger font size to source from for rendering on larger screens

const FontStorage = extern struct {
    texture: c.GLuint = undefined,
    baked_chars: [data.glyph_count]c.stbtt_bakedchar = undefined,
    texture_side_size: usize,

    const Self = @This();

    fn initWithFontData(allocator: Allocator, font: [:0]const u8, font_size: usize) !Self {
        const float_font_size: f32 = @floatFromInt(font_size);
        const size: usize = @intFromFloat(float_font_size * @ceil(@sqrt(@as(f32, @floatFromInt(data.glyph_count))) + 1)); // this should be enough?!
        var self: Self = .{ .texture_side_size = size };

        const buffer = try allocator.alloc(u8, size * size);
        defer allocator.free(buffer);
        _ = c.stbtt_BakeFontBitmap(font, 0, float_font_size, @ptrCast(buffer), @intCast(size), @intCast(size), data.first_char, data.glyph_count, &self.baked_chars);

        c.glGenTextures(1, &self.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R8, @intCast(size), @intCast(size), 0, c.GL_RED, c.GL_UNSIGNED_BYTE, @ptrCast(buffer));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteriv(c.GL_TEXTURE_2D, c.GL_TEXTURE_SWIZZLE_RGBA, &font_texture_swizzle_mask);

        return self;
    }
};

const FontData = struct {
    font_info: c.stbtt_fontinfo = undefined,
    ascent: c_int = undefined,
    descent: c_int = undefined,
    line_gap: c_int = undefined,
    loaded_fonts: HashMap(usize, FontStorage),
    allocator: Allocator,
    font: [:0]const u8,

    const Self = @This();

    fn init(allocator: Allocator, font: [:0]const u8) !Self {
        var self = Self{
            .allocator = allocator,
            .loaded_fonts = HashMap(usize, FontStorage).init(allocator),
            .font = font,
        };

        std.debug.assert(c.stbtt_InitFont(&self.font_info, font, 0) != 0);
        c.stbtt_GetFontVMetrics(&self.font_info, &self.ascent, &self.descent, &self.line_gap);

        return self;
    }

    fn loadFont(self: *Self, font_size: usize) void {
        const sourced_font_size = font_size * font_render_size_multiplier;
        if (self.loaded_fonts.contains(sourced_font_size)) return;
        const font_storage = FontStorage.initWithFontData(self.allocator, self.font, sourced_font_size) catch @panic("allocation error");
        self.loaded_fonts.put(sourced_font_size, font_storage) catch @panic("allocation error");
    }

    fn clear(self: *Self) void {
        var storage_iterator = self.loaded_fonts.valueIterator();
        while (storage_iterator.next()) |storage| {
            c.glDeleteTextures(1, &storage.texture);
        }
        self.loaded_fonts.clearRetainingCapacity();
    }

    fn deinit(self: *Self) void {
        var storage_iterator = self.loaded_fonts.valueIterator();
        while (storage_iterator.next()) |storage| {
            c.glDeleteTextures(1, &storage.texture);
        }
        self.loaded_fonts.deinit();
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
    serif_font_data: FontData,
    sans_serif_font_data: FontData,
    monospace_font_data: FontData,
    file_drop_image: ?ImageData = null,
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
            .serif_font_data = try FontData.init(allocator, data.serif_font),
            .sans_serif_font_data = try FontData.init(allocator, data.sans_serif_font),
            .monospace_font_data = try FontData.init(allocator, data.monospace_font),
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
        if (self.file_drop_image) |*image_data| {
            c.glDeleteTextures(1, &image_data.texture);
            self.file_drop_image = null;
        }

        self.serif_font_data.deinit();
        self.sans_serif_font_data.deinit();
        self.monospace_font_data.deinit();
    }

    pub fn clear(self: *Self) void {
        self.obj_buffer.clearRetainingCapacity();
        var iterator = self.images.valueIterator();
        while (iterator.next()) |image_data| {
            c.glDeleteTextures(1, &image_data.texture);
        }
        self.images.clearRetainingCapacity();
        if (self.file_drop_image) |*image_data| {
            c.glDeleteTextures(1, &image_data.texture);
            self.file_drop_image = null;
        }

        self.serif_font_data.clear();
        self.sans_serif_font_data.clear();
        self.monospace_font_data.clear();
    }

    pub fn loadSlideData(self: *Self, slide_show: *SlideShow) void {
        for (slide_show.slides.items) |*slide| {
            for (slide.sections.items) |*section| {
                switch (section.section_type) {
                    .image => |image_source| {
                        switch (image_source) {
                            .path => |*path| {
                                if (self.images.contains(path.items)) continue;

                                var width: c_int = undefined;
                                var height: c_int = undefined;
                                var num_channels: c_int = undefined;
                                const desired_channels: c_int = 4;
                                const image = c.stbi_load(@ptrCast(path.items), &width, &height, &num_channels, desired_channels);
                                std.debug.assert(num_channels == desired_channels);

                                const tex_id = generateTexture(image, width, height);
                                c.stbi_image_free(image);
                                const image_data: ImageData = .{ .texture = tex_id, .width = @intCast(width), .height = @intCast(height) };
                                self.images.put(path.items, image_data) catch @panic("allocation error");
                            },
                            .file_drop_image => {
                                if (self.file_drop_image != null) continue;

                                var width: c_int = undefined;
                                var height: c_int = undefined;
                                var num_channels: c_int = undefined;
                                const desired_channels: c_int = 4;
                                const image = c.stbi_load_from_memory(@ptrCast(data.file_drop_image), data.file_drop_image.len, &width, &height, &num_channels, desired_channels);
                                std.debug.assert(num_channels == desired_channels);

                                const tex_id = generateTexture(image, width, height);
                                c.stbi_image_free(image);
                                self.file_drop_image = .{ .texture = tex_id, .width = @intCast(width), .height = @intCast(height) };
                            },
                        }
                    },
                    .text => {
                        const font_data = switch (section.font_style) {
                            .serif => &self.serif_font_data,
                            .sans_serif => &self.sans_serif_font_data,
                            .monospace => &self.monospace_font_data,
                        };
                        font_data.loadFont(section.text_size);
                    },
                    .space => {},
                }
            }
        }
    }

    pub fn render(self: *Self, slide_show: *SlideShow) !void {
        const slide = slide_show.currentSlide();
        clearScreen(slide.background_color);

        const min_x_start: f64 = 10; // in pixels
        var cursor_x: f64 = min_x_start; // x position in pixel units
        var cursor_y: f64 = 0; // y baseline position in pixel units

        for (slide.sections.items) |*section| {
            const font_data = switch (section.font_style) {
                .serif => &self.serif_font_data,
                .sans_serif => &self.sans_serif_font_data,
                .monospace => &self.monospace_font_data,
            };
            const line_height: f64 = @floatFromInt(font_data.ascent - font_data.descent);
            const sourced_font_size = section.text_size * font_render_size_multiplier;
            const font_display_scale: f64 = @as(f64, @floatFromInt(section.text_size)) / @as(f64, @floatFromInt(sourced_font_size)); // needed as we are not sourcing the font size that is displayed
            const inverse_viewport_height = 1.0 / @as(f64, @floatFromInt(data.viewport_resolution_reference[1])); // y-axis as scale reference
            const font_scale = @as(f64, @floatFromInt(sourced_font_size)) / line_height;

            const yadvance_font: f64 = -(line_height + @as(f64, @floatFromInt(font_data.line_gap))) * section.line_spacing; // in font units (analogous to the xadvance in font data but generic)
            const yadvance = yadvance_font * font_scale * font_display_scale; // this is the specific yadvance accounting for font sizes

            switch (section.section_type) {
                .space => |lines| {
                    cursor_y += yadvance * @as(f64, @floatFromInt(lines));
                },
                .text => |text| {
                    const font_storage = font_data.loaded_fonts.get(sourced_font_size).?;
                    const tex_id: c.GLuint = font_storage.texture;
                    const space_width = charFontWidth(' ', &font_storage, font_display_scale);
                    var line_iterator = data.SplitIterator{ .string = text.items, .delimiter = '\n' };

                    while (line_iterator.next()) |line| {
                        // check line width that fits and determine cursor start for alignment
                        var word_iterator = data.SplitIterator{ .string = line, .delimiter = ' ' };
                        var line_to_render_start: usize = 0;

                        // we do the entire render process until there are no more auto-line-breaks to resolve
                        // this while loop runs once for every rendered line (might be forced by auto-line-breaks)
                        while (word_iterator.next()) |first_word| {
                            // there is always at least one word in a line

                            var line_width: f64 = sliceFontWidth(first_word, &font_storage, font_display_scale);
                            var line_to_render_len: usize = first_word.len;

                            while (word_iterator.peek(1)) |word| {
                                const additional_width = space_width + sliceFontWidth(word, &font_storage, font_display_scale);

                                // We don't know wether or not the line fits on the whole screen.
                                // If we encounter a word that won't fit, we render the stuff that does and go to the next line while skipping the space in between.
                                if (line_width + additional_width > data.viewport_resolution_reference[0] - 2 * @as(usize, @intFromFloat(min_x_start))) break;

                                line_width += additional_width;
                                line_to_render_len += 1 + word.len; // don't forget the space
                                std.debug.assert(word_iterator.next() != null); // we peeked successfully
                            }

                            const line_to_render = line[line_to_render_start..line_to_render_start + line_to_render_len];
                            line_to_render_start += line_to_render_len + 1; // advance the start of the rest of the line to render for the next iteration (the +1 is for the space that didn't get rendered)

                            cursor_x = switch (section.alignment) {
                                .center => (data.viewport_resolution_reference[0] - line_width) / 2,
                                .right => data.viewport_resolution_reference[0] - line_width - min_x_start,
                                .left => min_x_start,
                            };

                            for (line_to_render) |char| {
                                const baked_char = &font_storage.baked_chars[@as(usize, @intCast(char)) - data.first_char];
                                // lines don't contain the trailing new-line character
                                switch (char) {
                                    ' ' => {
                                        cursor_x += baked_char.xadvance * font_display_scale;
                                    },
                                    else => {
                                        const x_pos = (cursor_x + baked_char.xoff * font_display_scale) * inverse_viewport_height;
                                        const y_pos = (cursor_y - line_height * font_scale * font_display_scale - baked_char.yoff * font_display_scale) * inverse_viewport_height;
                                        // the switch of the sign of the y-offset is done to keep the way projections are done

                                        const position = lina.vec3(@floatCast(x_pos), @floatCast(y_pos), 0.0); // the z coord might change in the future with support for layers

                                        // the baked char data used does not require scaling because it would just cancel out
                                        const scale = lina.Mat4.scale(.{ .x = @as(f32, @floatFromInt(baked_char.x1 - baked_char.x0)) / @as(f32, @floatFromInt(baked_char.y1 - baked_char.y0)), .y = 1.0, .z = 1.0, });
                                        const pixel_scale = lina.Mat4.scaleFromFactor(@floatCast(inverse_viewport_height * @as(f64, @floatFromInt(baked_char.y1 - baked_char.y0)) * font_display_scale));
                                        const trafo = lina.Mat4.translation(position).mul(scale).mul(pixel_scale);

                                        const font_texture_side_pixel_size: f32 = @floatFromInt(font_storage.texture_side_size);
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
                    }
                },
                .image => |image_source| {
                    const image_data = switch (image_source) {
                        .path => |*path| self.images.get(path.items).?,
                        .file_drop_image => self.file_drop_image.?,
                    };
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

    /// computes the width of a slice of characters for some font
    fn sliceFontWidth(slice: []const u8, font_storage: *const FontStorage, font_display_scale: f64) f64 {
        var width: f64 = 0;
        for (slice) |char| {
            width += charFontWidth(char, font_storage, font_display_scale);
        }
        return width;
    }

    fn charFontWidth(char: u8, font_storage: *const FontStorage, font_display_scale: f64) f64 {
        const baked_char = &font_storage.baked_chars[@as(usize, @intCast(char)) - data.first_char];
        return baked_char.xadvance * font_display_scale;
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
        try self.obj_buffer.ensureTotalCapacity(self.max_num_meshes * data.plane_vertices.len);

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
