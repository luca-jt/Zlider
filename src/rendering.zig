const c = @import("c.zig");
const data = @import("data.zig");
const std = @import("std");
const HashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const viewport_ratio = @import("window.zig").viewport_ratio;
const SlideShow = @import("slides.zig").SlideShow;

void clear_screen(color: data.Color32) void {
    const float_color = color.toVec4();
    c.glClearColor(float_color.x, float_color.y, float_color.z, float_color.w);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
}

fn compile_shader(src: [:0]const c.GLchar, ty: c.GLenum) c.GLuint {
    const shader = c.glCreateShader(ty);
    c.glShaderSource(shader, 1, src, null);
    c.glCompileShader(shader);

    var status = c.GL_FALSE;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);

    if (status != c.GL_TRUE) {
        var len: c.GLint = 0;
        c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &len);
        var buf = std.heap.page_allocator.allocSentinel(c.GLchar, @intCast(len) * @sizeOf(c.GLchar) + 1, 0);
        defer std.heap.page_allcator.free(buf);
        c.glGetShaderInfoLog(shader, len, null, buf);
        @panic(buf);
    }
    return shader;
}

fn link_program(vs: c.GLuint, fs: c.GLuint) c.GLuint {
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
        var buf = std.heap.page_allocator.allocSentinel(c.GLchar, @intCast(len) * @sizeOf(c.GLchar) + 1, 0);
        defer std.heap.page_allcator.free(buf);
        c.glGetProgramInfoLog(program, len, null, buf);
        @panic(buf);
    }
    return program;
}

fn create_shader(vert: [:0]const c.GLchar, frag: [:0]const c.GLchar) c.GLuint {
    const vs = compile_shader(vert, c.GL_VERTEX_SHADER);
    const fs = compile_shader(frag, c.GL_FRAGMENT_SHADER);
    const id = link_program(vs, fs);
    c.glBindFragDataLocation(id, 0, "out_color");
    return id;
}

fn generate_texture(data: [:0]const u8, width: c.GLint, height: c.GLint) c.GLuint {
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
        data
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);

    return tex_id;
}

fn generate_white_texture() c.GLuint {
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
        white_color_data
    );
    return white_texture;
}

void copy_frame_buffer_to_memory(memory: [:0]u8) {
    c.glReadBuffer(c.GL_FRONT); // TODO: or GL_BACK?
    // TODO: (0,0) of the window or the viewport?
    c.glReadPixels(0, 0, window_state.vp_size_x, window_state.vp_size_y, c.GL_RGBA, c.GL_UNSIGNED_BYTE, memory);
    // TODO: flip the image vertically?
}

const Vertex = packed struct {
    position: Vec3,
    color: Vec4,
    uv: Vec2,
    tex_idx: c.GLfloat,
};

pub const Renderer = struct {
    shader: c.GLuint = create_shader(VERTEX_SHADER, FRAGMENT_SHADER),
    white_texture: c.GLuint = generate_white_texture(),
    vao: c.GLuint = 0,
    vbo: c.GLuint = 0,
    ibo: c.GLuint = 0,
    index_count: c.GLsizei = 0,
    obj_buffer: ArrayList(Vertex),
    all_tex_ids: ArrayList(c.GLuint),
    max_num_meshes: usize = 10,
    projection: Mat4 = MatrixOrtho(-viewport_ratio, viewport_ratio, -1.0, 1.0, 0.1, 2.0), // TODO
    view: Mat4 = MatrixLookAt((Vector3){0.0f, 0.0f, 1.0f}, (Vector3){0.0f, 0.0f, 0.0f}, (Vector3){0.0f, 1.0f, 0.0f}), // TODO
    textures: HashMap([]const u8, c.GLuint),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var r = Self{
            .obj_buffer = ArrayList(Vertex).init(allocator),
            .all_tex_ids = ArrayList(c.GLuint).init(allocator),
            .textures = HashMap([]const u8, c.GLuint).init(allocator),
        };
        usingnamespace r;

        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vao);
        c.glGenBuffers(1, &vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            plane_mesh_num_vertices * max_num_meshes * @sizeOf(Vertex),
            null,
            c.GL_DYNAMIC_DRAW
        );

        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(
            0,
            3,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "position")
        );

        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(
            1,
            4,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "color")
        );

        c.glEnableVertexAttribArray(2);
        c.glVertexAttribPointer(
            2,
            2,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "uv")
        );

        c.glEnableVertexAttribArray(3);
        c.glVertexAttribPointer(
            3,
            1,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "tex_idx")
        );

        const num_indices = plane_mesh_num_indices * max_num_meshes;
        var indices = try ArrayList(c.GLuint).initCapacity(allocator, num_indices);
        defer indices.deinit();

        for (0..num_indices) |i| {
            indices.appendAssumeCapactiy(data.plane_indices[i % plane_mesh_num_indices] + plane_mesh_num_vertices * (i / plane_mesh_num_indices));
        }

        c.glGenBuffers(1, &ibo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ibo);
        c.glBufferData(
            c.GL_ELEMENT_ARRAY_BUFFER,
            plane_mesh_num_indices * max_num_meshes * @sizeOf(c.GLuint),
            indices.items,
            c.GL_STATIC_DRAW
        );
        c.glBindVertexArray(0);

        return r;
    }

    pub fn deinit(self: Self) void {
        c.glDeleteProgram(self.shader);
        c.glDeleteTextures(1, &self.white_texture);
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteBuffers(1, &self.ibo);
        c.glDeleteVertexArrays(1, &self.vao);

        self.obj_buffer.deinit();
        self.all_tex_ids.deninit();

        for (self.textures.ValueIterator) |tex_id| {
            c.glDeleteTextures(1, &tex_id);
        }
        self.textures.deinit();
    }

    pub fn loadSlideData(self: *Self, slide_show: *SlideShow) void {
        for (&slide_show.slides.items) |*slide| {
            for (&slide.sections.items) |*section| {
                if (section.section_type != .image) continue;
                if (self.textures.contains(section.text.items)) continue;

                var width: c_int = undefined;
                var height: c_int = undefined;
                var num_channels: c_int = undefined;
                const data = c.stbi_load(section.text.items, &width, &height, &num_channels, 4);
                if (num_channels != 4) {
                    @panic("Image source does not have RGBA channels.");
                }

                const tex_id = generate_texture(data, width, height);
                c.stbi_image_free(data);
                self.textures.insert(section.text.items, tex_id);
            }
        }
    }

    pub fn render(self: *Self, slide_show: *SlideShow) void {
        const slide = slide_show.current_slide();
        clear_screen(slide.background_color);

        const current_cursor = slide.sections.items[0].text_size; // y position in pixels
        const line_spacing: usize = 2; // TODO: will be set in the slide files in the future

        for (&slide.sections.items) |section| {
            // TODO
        }

        self.flush();
    }

    fn flush(self: *Self) void {
        c.glUseProgram(self.shader);

        // copy the data to the GPU
        const vertices_size = self.obj_buffer.len * @sizeOf(Vertex);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferSubData(
            c.GL_ARRAY_BUFFER,
            0,
            vertices_size,
            self.obj_buffer.items
        );

        // bind uniforms
        c.glUniformMatrix4fv(0, 1, c.GL_FALSE, &self.projection);
        c.glUniformMatrix4fv(4, 1, c.GL_FALSE, &self.view);
        for (0..max_texture_count) |i| {
            c.glUniform1i(8 + i, i);
        }
        // bind texture
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.white_texture);

        // bind textures
        for (self.all_tex_ids.items, 0..) |tex_id, i| {
            const unit: c.GLenum = @intCast(i);
            const tex_id = self.all_tex_ids.items[i];
            c.glActiveTexture(c.GL_TEXTURE1 + unit);
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
};

const max_texture_count: usize = 32;
const plane_mesh_num_vertices: usize = 4;
const plane_mesh_num_indices: usize = 6;


void render_slide_show(SlideShow *slide_show, Renderer *renderer) {

    for (Section *section = slide->sections.items; section < section + slide->sections.len; section++) {
        const float scale_factor = (float)section->text_size / (float)window_state.vp_size[1];
        const Matrix image_scale = MatrixScale(scale_factor, scale_factor, scale_factor);

        switch (section->type) {
            case SPACE_SECTION:
            {
                current_cursor += section->text_size;
                current_cursor += line_spacing;
                break;
            }
            case TEXT_SECTION:
            {
                Vector3 position = {0}; // TODO
                Matrix trafo = MatrixMultiply(MatrixTranslate(position.x, position.y, position.z), image_scale);
                GLuint tex_id = 0; // TODO
                for (const char *ptr = section->text; *ptr; ptr++) {
                    if (*ptr == '\n') {
                        current_cursor += line_spacing; // TODO: other special chars and an x axis cursor
                    }
                    add_tex_quad(renderer, trafo, tex_id);
                }
                current_cursor += line_spacing;
                break;
            }
            case IMAGE_SECTION:
            {
                Vector3 position = {0}; // TODO
                Matrix trafo = MatrixMultiply(MatrixTranslate(position.x, position.y, position.z), image_scale);
                int64_t id_result = texture_table_get(&renderer->textures, section->text);
                CLIDER_ASSERT(id_result != -1, "Corrupted texture id.");
                GLuint tex_id = (GLuint)id_result;
                add_tex_quad(renderer, trafo, tex_id);
                current_cursor += line_spacing;
                break;
            }
        }
    }
    flush(renderer);
}

bool add_tex_quad(Renderer *renderer, Matrix trafo, c.GLuint tex_id) {
    // determine texture index
    c.GLfloat tex_idx = -1.0;
    for (size_t i = 0; i < renderer->all_tex_ids.len; i++) {
        c.GLuint id = renderer->all_tex_ids.items[i];
        if (id == tex_id) {
            tex_idx = (c.GLfloat)(i + 1);
            break;
        }
    }
    if (tex_idx == -1.0) {
        if (renderer->all_tex_ids.len >= MAX_TEXTURE_COUNT - 1) {
            // start a new batch if out of texture slots
            return false;
        }
        tex_idx = (c.GLfloat)(renderer->all_tex_ids.len + 1);
        GLuint_array_append(&renderer->all_tex_ids, tex_id);
    }
    if ((size_t)renderer->index_count >= plane_meshj_num_indices * renderer->max_num_meshes) {
        return false;
    }
    // copy mesh vertex data into the object buffer
    for (size_t i = 0; i < plane_mesh_num_vertices; i++) {
        Vertex vertex;
        vertex.position = Vector3Transform(PLANE_VERTICES[i], trafo);
        Vector4 vert_color = { 1.0f, 1.0f, 1.0f, 1.0f };
        vertex.color = vert_color;
        vertex.uv = PLANE_UVS[i];
        vertex.tex_idx = tex_idx;
        Vertex_array_append(&renderer->obj_buffer, vertex);
    }
    renderer->index_count += plane_meshj_num_indices;

    return true;
}

bool add_color_quad(Renderer *renderer, Matrix trafo, Color32 color) {
    if ((size_t)renderer->index_count >= plane_meshj_num_indices * renderer->max_num_meshes) {
        return false;
    }

    // copy mesh vertex data into the object buffer
    for (size_t i = 0; i < plane_mesh_num_vertices; i++) {
        Vertex vertex;
        vertex.position = Vector3Transform(PLANE_VERTICES[i], trafo);
        vertex.color = rgba_to_float(color);
        vertex.uv = PLANE_UVS[i];
        vertex.tex_idx = 0.0; // white texture
        Vertex_array_append(&renderer->obj_buffer, vertex);
    }
    renderer->index_count += plane_meshj_num_indices;

    return true;
}
