const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);
const HashMap = std.AutoHashMap;


fn read_entire_file(file_name: []const u8, allocator: Allocator) ![]u8 {
    const dir = std.fs.cwd();
    const buffer = dir.readFileAlloc(allocator, file_name, 4096);
    return buffer;
}


const Lexer = struct {
    line: usize,
    buffer: String;
    inside_comment: bool,
    file_aliases: HashMap([]const u8, []const u8),
    ptr: *const u8,
};


bool lexer_contains_keyword(Lexer *lexer) {
    for (size_t i = 0; i < RESERVED_NAMES_LEN; i++) {
        const char *name = RESERVED_NAMES[i];
        if (strcmp(lexer->buffer.chars, name) == 0) {
            return true;
        }
    }
    return false;
}


char *lexer_next_word(Lexer *lexer) {
    clear_string(&lexer->buffer);
    while (*lexer->ptr == ' ' || *lexer->ptr == '\t' || *lexer->ptr == '\n') {
        lexer->ptr++;
    }
    while (*lexer->ptr != '\0' && *lexer->ptr != ' ' && *lexer->ptr != '\t' && *lexer->ptr != '\n') {
        append_char(&lexer->buffer, *(lexer->ptr++));
    }
    return lexer->buffer.chars;
}


char *lexer_read_until_newline(Lexer* lexer) {
    clear_string(&lexer->buffer);
    while (*lexer->ptr == ' ' || *lexer->ptr == '\t' || *lexer->ptr == '\n') {
        lexer->ptr++;
    }
    while (*lexer->ptr != '\0' && *lexer->ptr != '\n') {
        append_char(&lexer->buffer, *(lexer->ptr++));
    }
    const char *eos = end_of_string(&lexer->buffer);
    while (*eos == ' ' || *eos == '\t') {
        pop_char(&lexer->buffer);
        eos = end_of_string(&lexer->buffer);
    }
    return lexer->buffer.chars;
}


Token next_token(Lexer *lexer) {
    clear_string(&lexer->buffer);
    Token token = {0};
    token.is_empty = false;

    while (*lexer->ptr == ' ' || *lexer->ptr == '\t' || *lexer->ptr == '\n') {
        lexer->ptr++;
    }

    while (*lexer->ptr != '\0') {
        char c = *(lexer->ptr++);

        if (c == '\n' && lexer->inside_comment) {
            lexer->inside_comment = false;
            clear_string(&lexer->buffer);
            lexer->line++;
            continue;
        }

        if (lexer->inside_comment) {
            continue;
        }

        if (c == ' ' || c == '\t' || c == '\0' || c == '\n') {
            if (lexer_contains_keyword(lexer)) {
                const char *keyword = lexer->buffer.chars;

                if (strcmp(keyword, RESERVED_NAMES[KW_TEXT_COLOR]) == 0) {
                    token.type = TOKEN_TEXT_COLOR;
                    const char *next_word = lexer_next_word(lexer);
                    token.color = rgba_from_hex(next_word);

                } else if (strcmp(keyword, RESERVED_NAMES[KW_BG]) == 0) {
                    token.type = TOKEN_BG;
                    const char *next_word = lexer_next_word(lexer);
                    token.color = rgba_from_hex(next_word);

                } else if (strcmp(keyword, RESERVED_NAMES[KW_SLIDE]) == 0) {
                    token.type = TOKEN_SLIDE;
                    token.is_empty = true;

                } else if (strcmp(keyword, RESERVED_NAMES[KW_DEFINE]) == 0) {
                    token.type = TOKEN_DEFINE;
                    const char *file = lexer_next_word(lexer);
                    append_string(&token.string, file);
                    const char *alias = lexer_next_word(lexer);
                    string_table_insert(&lexer->file_aliases, alias, token.string.chars);

                } else if (strcmp(keyword, RESERVED_NAMES[KW_CENTERED]) == 0) {
                    token.type = TOKEN_CENTERED;
                    token.is_empty = true;

                } else if (strcmp(keyword, RESERVED_NAMES[KW_LEFT]) == 0) {
                    token.type = TOKEN_LEFT;
                    token.is_empty = true;

                } else if (strcmp(keyword, RESERVED_NAMES[KW_RIGHT]) == 0) {
                    token.type = TOKEN_RIGHT;
                    token.is_empty = true;

                } else if (strcmp(keyword, RESERVED_NAMES[KW_TEXT]) == 0) {
                    token.type = TOKEN_TEXT;
                    const char *next_line = lexer_read_until_newline(lexer);
                    while (strcmp(next_line, "text") != 0) {
                        append_string(&token.string, next_line);
                        append_char(&token.string, '\n');
                        next_line = lexer_read_until_newline(lexer);
                    }

                } else if (strcmp(keyword, RESERVED_NAMES[KW_SPACE]) == 0) {
                    token.type = TOKEN_SPACE;
                    const char *next_word = lexer_next_word(lexer);
                    token.size = (size_t)strtoul(next_word, NULL, 10);

                } else if (strcmp(keyword, RESERVED_NAMES[KW_TEXT_SIZE]) == 0) {
                    token.type = TOKEN_TEXT_SIZE;
                    const char *next_word = lexer_next_word(lexer);
                    token.size = (size_t)strtoul(next_word, NULL, 10);

                } else if (strcmp(keyword, RESERVED_NAMES[KW_IMAGE]) == 0) {
                    token.type = TOKEN_FILE;
                    const char *next_word = lexer_next_word(lexer);
                    append_string(&token.string, next_word);

                } else {
                    CLIDER_LOG_ERROR("This should never happen. Error in identifier lookup.");
                    token.type = TOKEN_ERROR;
                    token.is_empty = true;
                }
            } else if (string_table_get(&lexer->file_aliases, lexer->buffer.chars)) {
                token.type = TOKEN_FILE;
                const char *alias = string_table_get(&lexer->file_aliases, lexer->buffer.chars);
                append_string(&token.string, alias);
            } else {
                report_parse_error(lexer->line, &lexer->buffer);
                token.type = TOKEN_ERROR;
                token.is_empty = true;
            }

            return token;
        }

        if (c == '/' && lexer->buffer.chars[lexer->buffer.len - 2] == '/') {
            lexer->inside_comment = true;
            continue;
        }

        append_char(&lexer->buffer, c);
    }

    token.type = TOKEN_NONE;
    token.is_empty = true;
    return token;
}


void new_section(Section *section, Slide *slide) {
    size_t prev_text_size = section->text_size;
    Color32 prev_text_color = section->text_color;
    ElementAlignment prev_align = section->alignment;
    Section_array_append(&slide->sections, *section);
    *section = (Section){0};
    section->text_size = prev_text_size;
    section->text_color = prev_text_color;
    section->alignment = prev_align;
}


void parse_slide_show_file(SlideShow *slide_show, EntireFile *file) {
    Lexer lexer = {0};
    lexer.inside_comment = false;
    lexer.ptr = (char*)file->contents;
    lexer.file_aliases = string_table_create();

    Slide slide = {0};
    Section section = {0};
    section.text_size = 12;
    section.text_color = (Color32){ 0, 0, 0, 255 };
    bool first_slide = true;
    bool first_section = true;

    Token token;
    do {
        token = next_token(&lexer);

        switch (token.type) {
            case TOKEN_NONE:
            case TOKEN_ERROR:
                break;

            case TOKEN_FILE:
                {
                    if (first_section) {
                        first_section = false;
                        break;
                    }
                    new_section(&section, &slide);
                    section.type = IMAGE_SECTION;
                    section.text = token.string.chars;
                    break;
                }

            case TOKEN_BG:
                slide.background_color = token.color;
                break;

            case TOKEN_SLIDE:
                {
                    if (first_slide) {
                        first_slide = false;
                        break;
                    }
                    new_section(&section, &slide);

                    Color32 prev_bg_color = slide.background_color;
                    Slide_array_append(&slide_show->slides, slide);

                    slide = (Slide){0};
                    slide.background_color = prev_bg_color;

                    first_section = true;
                    break;
                }

            case TOKEN_SPACE:
                {
                    if (first_section) {
                        first_section = false;
                        break;
                    }
                    new_section(&section, &slide);
                    section.lines = token.size;
                    break;
                }

            case TOKEN_TEXT_SIZE:
                section.text_size = token.size;
                break;

            case TOKEN_CENTERED:
                section.alignment = ALIGN_CENTER;
                break;

            case TOKEN_TEXT:
                {
                    if (first_section) {
                        first_section = false;
                        break;
                    }
                    new_section(&section, &slide);
                    section.type = TEXT_SECTION;
                    section.text = token.string.chars;
                    break;
                }

            case TOKEN_RIGHT:
                section.alignment = ALIGN_RIGHT;
                break;

            case TOKEN_LEFT:
                section.alignment = ALIGN_LEFT;
                break;

            case TOKEN_DEFINE:
                free_string(&token.string);
                break;

            case TOKEN_TEXT_COLOR:
                section.text_color = token.color;
                break;
        }
    } while (token.type != TOKEN_NONE && token.type != TOKEN_ERROR);

    if (token.type == TOKEN_NONE) {
        Section_array_append(&slide.sections, section);
        Slide_array_append(&slide_show->slides, slide);
    }

    free_string(&lexer.buffer);
    string_table_drop(&lexer.file_aliases);

    if (token.type == TOKEN_ERROR) {
        exit(1);
    }

    if (slide_show->slides.len < 1 || slide_show->slides.len > 999) {
        CLIDER_LOG_ERROR("The number of slides has to be between 1 and 999.");
        exit(1);
    }
}


SlideShow slide_show_from_file(const char *file_name) {
    SlideShow slide_show = {0};

    EntireFile file = read_entire_file(file_name);
    if (!file.contents) {
        return slide_show;
    }

    slide_show.title = file_name;
    parse_slide_show_file(&slide_show, &file);

    free_entire_file(&file);

    return slide_show;
}


void drop_slide_show(SlideShow *slide_show) {
    for (size_t i = 0; i < slide_show->slides.len; i++) {
        Slide *slide = &slide_show->slides.items[i];
        for (Section *section = slide->sections.items; section < section + slide->sections.len; section++) {
            if (section->type != SPACE_SECTION) {
                free((void*)section->text); // this is done because the ownership of the section text was transfered previously in the token generation
            }
        }
        Section_array_free(&slide->sections);
    }
    Slide_array_free(&slide_show->slides);
}


void render_slide_show(SlideShow *slide_show, Renderer *renderer) {
    Slide *slide = current_slide(slide_show);
    clear_screen(slide->background_color);
    size_t current_cursor = slide->sections.items[0].text_size; // y position in pixels

    const size_t line_spacing = 2; // TODO: will be set in the slide files in the future

    for (Section *section = slide->sections.items; section < section + slide->sections.len; section++) {
        const float scale_factor = (float)section->text_size / (float)WINDOW_STATE.vp_size[1];
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


void handle_input(GLFWwindow *window, SlideShow *slide_show, Renderer *renderer) {
    // fullscreen toggle
    if (c.glfwGetKey(window, c.GLFW_KEY_F11) == c.GLFW_PRESS) {
        c.GLFWmonitor* monitor = c.glfwGetPrimaryMonitor();
        if (!c.glfwGetWindowMonitor(window)) {
            update_window_attributes(window);
            const c.GLFWvidmode *mode = c.glfwGetVideoMode(monitor);
            c.glfwSetWindowMonitor(window, monitor, 0, 0, mode->width, mode->height, c.GLFW_DONT_CARE);
        } else {
            c.glfwSetWindowMonitor(window, NULL, WINDOW_STATE.win_pos[0], WINDOW_STATE.win_pos[1], WINDOW_STATE.win_size[0], WINDOW_STATE.win_size[1], c.GLFW_DONT_CARE);
        }
    }
    // slide_show_switch
    if (c.glfwGetKey(window, c.GLFW_KEY_RIGHT) == c.GLFW_PRESS || c.glfwGetKey(window, c.GLFW_KEY_DOWN) == c.GLFW_PRESS) {
        if (slide_show->current_slide < slide_show->slides.len - 1) {
            slide_show->current_slide++;
        }
    }
    if (c.glfwGetKey(window, c.GLFW_KEY_LEFT) == c.GLFW_PRESS || c.glfwGetKey(window, c.GLFW_KEY_UP) == c.GLFW_PRESS) {
        if (slide_show->current_slide > 0) {
            slide_show->current_slide--;
        }
    }
    // dump the slides to png
    if (c.glfwGetKey(window, c.GLFW_KEY_I) == c.GLFW_PRESS) {
        size_t current_slide_idx = slide_show->current_slide;
        slide_show->current_slide = 0;
        void *slide_mem = malloc(WINDOW_STATE.vp_size[0] * WINDOW_STATE.vp_size[1] * 4);
        CLIDER_DEBUG_ASSERT(slide_mem, "allocation for frame image failed");

        int compression_level = 5;

        StringBuilder slide_name = {0};
        append_string(&slide_name, slide_show->title);
        append_string(&slide_name, "_000");
        char *number_string = &slide_name.chars[slide_name.len - 1];
        number_string -= 3;

        while (slide_show->current_slide < slide_show->slides.len) {
            int slide_number = slide_show->current_slide + 1;
            sprintf(number_string, "%03d", slide_number);
            render_slide_show(slide_show, renderer);
            copy_frame_buffer_to_memory(slide_mem);

            c.stbi_write_png(slide_name.chars, WINDOW_STATE.vp_size[0], WINDOW_STATE.vp_size[1], compression_level, slide_mem, 4);
            slide_show->current_slide++;
        }

        free(slide_mem);
        free_string(&slide_name);
        slide_show->current_slide = current_slide_idx;
    }
}
