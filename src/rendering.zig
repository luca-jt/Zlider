const c = @import("c.zig");

void clear_screen(color: Color32) void {
    const float_color = color.to_vec4();
    c.glClearColor(float_color.x, float_color.y, float_color.z, float_color.w);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
}

fn compile_shader(const c.GLchar *src, c.GLenum ty) c.GLuint {
    GLuint shader = c.glCreateShader(ty);
    c.glShaderSource(shader, 1, &src, null);
    c.glCompileShader(shader);

    var status = c.GL_FALSE;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);

    if (status != c.GL_TRUE) {
        c.GLint len = 0;
        c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &len);
        c.GLchar *buf = (char*)malloc(len * sizeof(char) + 1);
        buf[len] = '\0';
        c.glGetShaderInfoLog(shader, len, null, buf);
        CLIDER_LOG_ERROR(buf);
        free((void*)buf);
        exit(EXIT_FAILURE);
    }
    return shader;
}


c.GLuint link_program(c.GLuint vs, c.GLuint fs) {
    c.GLuint program = c.glCreateProgram();
    c.glAttachShader(program, vs);
    c.glAttachShader(program, fs);
    c.glLinkProgram(program);

    c.glDetachShader(program, fs);
    c.glDetachShader(program, vs);
    c.glDeleteShader(fs);
    c.glDeleteShader(vs);

    c.GLint status = c.GL_FALSE;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &status);

    if (status != c.GL_TRUE) {
        c.GLint len = 0;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &len);
        c.GLchar *buf = (char*)malloc(len * sizeof(char) + 1);
        buf[len] = '\0';
        c.glGetProgramInfoLog(program, len, null, buf);
        CLIDER_LOG_ERROR(buf);
        free((void*)buf);
        exit(EXIT_FAILURE);
    }
    return program;
}


c.GLuint create_shader(const c.GLchar *vert, const c.GLchar *frag) {
    c.GLuint vs = compile_shader(vert, c.GL_VERTEX_SHADER);
    c.GLuint fs = compile_shader(frag, c.GL_FRAGMENT_SHADER);
    c.GLuint id = link_program(vs, fs);
    c.glBindFragDataLocation(id, 0, "out_color");
    return id;
}


c.GLuint generate_texture(unsigned char *data, c.GLint width, c.GLint height) {
    c.GLuint tex_id = 0;
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
        (void*)data
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);

    return tex_id;
}


c.GLuint generate_white_texture(void) {
    c.GLuint white_texture = 0;
    c.glGenTextures(1, &white_texture);
    c.glBindTexture(c.GL_TEXTURE_2D, white_texture);
    uint8_t white_color_data[4] = { 255, 255, 255, 255 };
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA8,
        1,
        1,
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        (void*)white_color_data
    );
    return white_texture;
}


void copy_frame_buffer_to_memory(void *memory) {
    c.glReadBuffer(c.GL_FRONT); // TODO: or GL_BACK?
    // TODO: (0,0) of the window or the viewport?
    c.glReadPixels(0, 0, WINDOW_STATE.vp_size[0], WINDOW_STATE.vp_size[1], c.GL_RGBA, c.GL_UNSIGNED_BYTE, memory);
    // TODO: flip the image vertically?
}


typedef struct {
    Vector3 position;
    Vector4 color;
    Vector2 uv;
    c.GLfloat tex_idx;
} Vertex;


typedef struct {
    c.GLuint shader;
    c.GLuint white_texture;
    c.GLuint vao;
    c.GLuint vbo;
    c.GLuint ibo;
    c.GLsizei index_count;
    Vertex_Array obj_buffer;
    GLuint_Array all_tex_ids;
    size_t max_num_meshes;
    Matrix projection;
    Matrix view;
    TextureHashTable textures;
} Renderer;


const max_texture_count: usize = 32;
const plane_mesh_num_vertices: usize = 4;
const plane_meshj_num_indices: usize = 6;


void init_renderer(Renderer *renderer, SlideShow *slide_show) {
    renderer->shader = create_shader(VERTEX_SHADER, FRAGMENT_SHADER);
    renderer->white_texture = generate_white_texture();
    renderer->index_count = 0;
    renderer->obj_buffer = (Vertex_Array){0};
    renderer->all_tex_ids = (GLuint_Array){0};
    renderer->max_num_meshes = 10;

    c.GLuint vao = 0;
    c.GLuint vbo = 0;
    c.GLuint ibo = 0;
    c.glGenVertexArrays(1, &vao);
    c.glBindVertexArray(vao);
    c.glGenBuffers(1, &vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        plane_mesh_num_vertices * renderer->max_num_meshes * sizeof(Vertex),
        null,
        c.GL_DYNAMIC_DRAW
    );

    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(
        0,
        3,
        c.GL_FLOAT,
        c.GL_FALSE,
        sizeof(Vertex),
        (void*)offsetof(Vertex, position)
    );

    c.glEnableVertexAttribArray(1);
    c.glVertexAttribPointer(
        1,
        4,
        c.GL_FLOAT,
        c.GL_FALSE,
        sizeof(Vertex),
        (void*)offsetof(Vertex, color)
    );

    c.glEnableVertexAttribArray(2);
    c.glVertexAttribPointer(
        2,
        2,
        c.GL_FLOAT,
        c.GL_FALSE,
        sizeof(Vertex),
        (void*)offsetof(Vertex, uv)
    );

    c.glEnableVertexAttribArray(3);
    c.glVertexAttribPointer(
        3,
        1,
        c.GL_FLOAT,
        c.GL_FALSE,
        sizeof(Vertex),
        (void*)offsetof(Vertex, tex_idx)
    );

    GLuint_Array indices = {0};
    size_t num_indices = plane_meshj_num_indices * renderer->max_num_meshes;
    GLuint_array_reserve(&indices, num_indices);
    for (size_t i = 0; i < num_indices; i++) {
        indices.items[i] = PLANE_INDICES[i % plane_meshj_num_indices] + plane_mesh_num_vertices * (i / plane_meshj_num_indices);
    }
    c.glGenBuffers(1, &ibo);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ibo);
    c.glBufferData(
        c.GL_ELEMENT_ARRAY_BUFFER,
        plane_meshj_num_indices * renderer->max_num_meshes * sizeof(GLuint),
        indices.items,
        c.GL_STATIC_DRAW
    );
    c.glBindVertexArray(0);
    GLuint_array_free(&indices);

    renderer->vao = vao;
    renderer->vbo = vbo;
    renderer->ibo = ibo;

    renderer->projection = MatrixOrtho(-VIEWPORT_RATIO, VIEWPORT_RATIO, -1.0, 1.0, 0.1, 2.0);
    renderer->view = MatrixLookAt((Vector3){0.0f, 0.0f, 1.0f}, (Vector3){0.0f, 0.0f, 0.0f}, (Vector3){0.0f, 1.0f, 0.0f});

    renderer->textures = texture_table_create();

    for (Slide *slide = slide_show->slides.items; slide < slide + slide_show->slides.len; slide++) {
        for (Section *section = slide->sections.items; section < section + slide->sections.len; section++) {
            if (section->type != IMAGE_SECTION) {
                continue;
            }
            int64_t id = texture_table_get(&renderer->textures, section->text);
            if (id != -1) {
                continue;
            }
            int width, height, num_channels;
            unsigned char *data = stbi_load(section->text, &width, &height, &num_channels, 4);
            if (num_channels != 4) {
                StringBuilder msg = {0};
                append_string(&msg, "Image source '");
                append_string(&msg, section->text);
                append_string(&msg, "' does not have RGBA channels.");
                CLIDER_LOG_ERROR(msg.chars);
                free_string(&msg);
                exit(1);
            }
            GLuint tex_id = generate_texture(data, width, height);
            stbi_image_free(data);
            texture_table_insert(&renderer->textures, section->text, tex_id);
        }
    }
}


void flush(Renderer *renderer) {
    c.glUseProgram(renderer->shader);

    // copy the data to the GPU
    c.GLsizeiptr vertices_size = renderer->obj_buffer.len * sizeof(Vertex);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, renderer->vbo);
    c.glBufferSubData(
        c.GL_ARRAY_BUFFER,
        0,
        vertices_size,
        renderer->obj_buffer.items
    );

    // bind uniforms
    c.glUniformMatrix4fv(0, 1, c.GL_FALSE, (c.GLfloat*)&renderer->projection);
    c.glUniformMatrix4fv(4, 1, c.GL_FALSE, (c.GLfloat*)&renderer->view);
    for (size_t i = 0; i < MAX_TEXTURE_COUNT; i++) {
        c.glUniform1i(8 + i, i);
    }
    // bind texture
    c.glActiveTexture(c.GL_TEXTURE0);
    c.glBindTexture(c.GL_TEXTURE_2D, renderer->white_texture);

    // bind textures
    for (size_t i = 0; i < renderer->all_tex_ids.len; i++) {
        c.GLenum unit = i;
        c.GLuint tex_id = renderer->all_tex_ids.items[i];
        c.glActiveTexture(c.GL_TEXTURE1 + unit);
        c.glBindTexture(c.GL_TEXTURE_2D, tex_id);
    }
    // draw the triangles corresponding to the index buffer
    c.glBindVertexArray(renderer->vao);
    c.glDrawElements(
        c.GL_TRIANGLES,
        renderer->index_count,
        c.GL_UNSIGNED_INT,
        null
    );
    c.glBindVertexArray(0);

    renderer->index_count = 0;
    renderer->obj_buffer.len = 0;
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


void drop_renderer(Renderer *renderer) {
    c.glDeleteProgram(renderer->shader);
    c.glDeleteTextures(1, &renderer->white_texture);
    c.glDeleteBuffers(1, &renderer->vbo);
    c.glDeleteBuffers(1, &renderer->ibo);
    c.glDeleteVertexArrays(1, &renderer->vao);
    Vertex_array_free(&renderer->obj_buffer);
    GLuint_array_free(&renderer->all_tex_ids);

    for (size_t i = 0; i < renderer->textures.size; i++) {
        struct texture_elt *elt = renderer->textures.table[i];
        while (elt) {
            c.glDeleteTextures(1, &elt->value);
            elt = elt->next;
        }
    }

    texture_table_drop(&renderer->textures);
}
