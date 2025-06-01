const c = @import("c.zig");
const data = @import("data.zig");
const std = @import("std");
const HashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const win = @import("window.zig");
const state = @import("state.zig");
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
        const buf = alloc.allocator().allocSentinel(c.GLchar, @as(usize, @intCast(len)) * @sizeOf(c.GLchar) + 1, 0) catch unreachable;
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
        const buf = alloc.allocator().allocSentinel(c.GLchar, @as(usize, @intCast(len)) * @sizeOf(c.GLchar) + 1, 0) catch unreachable;
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
    position: zlm.Vec4,
    color: zlm.Vec4,
    uv: zlm.Vec2,
    tex_idx: c.GLfloat,
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
    max_num_meshes: usize = 10,
    projection: zlm.Mat4 = zlm.Mat4.ortho(-win.viewport_ratio, win.viewport_ratio, -1.0, 1.0, 0.1, 2.0),
    view: zlm.Mat4 = zlm.Mat4.lookAt(zlm.Vec3.unitZ, zlm.Vec3.zero, zlm.Vec3.unitY),
    textures: HashMap(c.GLuint),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var r = Self{
            .shader = createShader(data.vertex_shader, data.fragment_shader),
            .white_texture = generateWhiteTexture(),
            .obj_buffer = ArrayList(Vertex).init(allocator),
            .all_tex_ids = ArrayList(c.GLuint).init(allocator),
            .textures = HashMap(c.GLuint).init(allocator),
        };

        c.glGenVertexArrays(1, &r.vao);
        c.glBindVertexArray(r.vao);
        c.glGenBuffers(1, &r.vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, r.vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(data.plane_vertices.len * r.max_num_meshes * @sizeOf(Vertex)),
            null,
            c.GL_DYNAMIC_DRAW
        );
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(
            0,
            4,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(@offsetOf(Vertex, "position"))
        );
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(
            1,
            4,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(@offsetOf(Vertex, "color"))
        );
        c.glEnableVertexAttribArray(2);
        c.glVertexAttribPointer(
            2,
            2,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(@offsetOf(Vertex, "uv"))
        );
        c.glEnableVertexAttribArray(3);
        c.glVertexAttribPointer(
            3,
            1,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(@offsetOf(Vertex, "tex_idx"))
        );

        const num_indices = data.plane_indices.len * r.max_num_meshes;
        var indices = try ArrayList(c.GLuint).initCapacity(allocator, num_indices);
        defer indices.deinit();

        for (0..num_indices) |i| {
            indices.appendAssumeCapacity(@intCast(data.plane_indices[i % data.plane_indices.len] + data.plane_vertices.len * (i / data.plane_indices.len)));
        }

        c.glGenBuffers(1, &r.ibo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, r.ibo);
        c.glBufferData(
            c.GL_ELEMENT_ARRAY_BUFFER,
            @intCast(data.plane_indices.len * r.max_num_meshes * @sizeOf(c.GLuint)),
            @ptrCast(indices.items),
            c.GL_STATIC_DRAW
        );
        c.glBindVertexArray(0);

        return r;
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
                self.textures.put(section.data.text.items, tex_id) catch unreachable;
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

        var current_cursor = slide.sections.items[0].text_size; // y position in pixels
        const line_spacing: usize = 2; // TODO: will be set in the slide files in the future

        for (slide.sections.items) |*section| {
            const scale_factor = @as(f32, @floatFromInt(section.text_size)) / @as(f32, @floatFromInt(state.window_state.vp_size_y));
            const image_scale = zlm.Mat4.scaleFromFactor(scale_factor);

            switch (section.section_type) {
                .space => {
                    current_cursor += section.text_size;
                    current_cursor += line_spacing;
                },
                .text => {
                    const position = zlm.Vec3.zero; // TODO
                    const trafo = zlm.Mat4.translation(position).mul(image_scale);
                    const tex_id: c.GLuint = 0; // TODO
                    for (section.data.text.items) |char| {
                        if (char == '\n') {
                            current_cursor += line_spacing; // TODO: other special chars and an x axis cursor
                        }
                        _ = try self.addTexQuad(trafo, tex_id); // TODO: return value
                    }
                    current_cursor += line_spacing;
                },
                .image => {
                    const position = zlm.Vec3.zero; // TODO
                    const trafo = zlm.Mat4.translation(position).mul(image_scale);
                    const tex_id = self.textures.get(section.data.text.items).?;
                    _ = try self.addTexQuad(trafo, tex_id); // TODO: return value
                    current_cursor += line_spacing;
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

    fn addTexQuad(self: *Self, trafo: zlm.Mat4, tex_id: c.GLuint) !bool {
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
            try self.all_tex_ids.append(tex_id);
        }
        if (self.index_count >= data.plane_indices.len * self.max_num_meshes) {
            return false;
        }
        // copy mesh vertex data into the object buffer
        for (0..data.plane_vertices.len) |i| {
            const v4 = zlm.vec4(data.plane_vertices[i].x, data.plane_vertices[i].y, data.plane_vertices[i].z, 1.0);
            try self.obj_buffer.append(.{
                .position = v4.transform(trafo),
                .color = zlm.Vec4.fromElement(1.0),
                .uv = data.plane_uvs[i],
                .tex_idx = tex_idx,
            });
        }
        self.index_count += data.plane_indices.len;
        return true;
    }

    fn addColorQuad(self: Self, trafo: zlm.Mat4, color: data.Color32) !bool {
        if (self.index_count >= data.plane_indices.len * self.max_num_meshes) {
            return false;
        }
        // copy mesh vertex data into the object buffer
        for (0..data.plane_vertices.len) |i| {
            const v4 = zlm.vec4(data.plane_vertices[i].x, data.plane_vertices[i].y, data.plane_vertices[i].z, 1.0);
            try self.obj_buffer.append(.{
                .position = v4.transform(trafo),
                .color = color.toVec4(),
                .uv = data.plane_uvs[i],
                .tex_idx = 0.0, // white texture
            });
        }
        self.index_count += data.plane_indices.len;
        return true;
    }
};

const max_texture_count: usize = 32;
