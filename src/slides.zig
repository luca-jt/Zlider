const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
pub const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const HashMap = std.AutoHashMap;
const data = @import("data.zig");

fn read_entire_file(file_name: []const u8, allocator: Allocator) !String {
    const dir = std.fs.cwd();
    const buffer = try dir.readFileAlloc(allocator, file_name, 4096);
    var string = String.fromOwnedSlice(allocator, buffer);
    string.append('\0'); // do this for lexing pointer stuff
    return string;
}

pub const LexError = error {
    NoKeywordValue,
    NoClosingKeyword,
    UnknownKeyword,
};

const Lexer = struct {
    line: usize = 0,
    buffer: String = String.init(std.heap.page_allocator),
    ptr: *const u8,

    const Self = @This();

    fn containedKeyword(self: *Self) ?data.Keyword {
        for (data.reserved_names, 0..) |name, i| {
            if (self.buffer.items == name) {
                return @enumFromInt(i);
            }
        }
        return null;
    }

    fn skipWhiteSpace(self: *Self) void {
        while (self.ptr.* == ' ' or self.ptr.* == '\t' or self.ptr.* == '\n') {
            if (self.ptr.* == '\n') self.line += 1;
            self.ptr += 1;
        }
    }

    fn readChar(self: *Self) void {
        self.buffer.append(self.ptr.*);
        self.ptr += 1;
    }

    fn readNextWord(self: *Self) LexError![]const u8 {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();

        while (self.ptr.* != '\0' and self.ptr.* != ' ' and self.ptr.* != '\t' and self.ptr.* != '\n') {
            self.readChar();
        }
        if (self.buffer.len == 0) return LexError.NoKeywordValue;
        return self.buffer.items;
    }

    fn readUntilNewLine(self: *Self) []const u8 {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();

        while (self.ptr.* != '\0' and self.ptr.* != '\n') {
            self.readChar();
        }
        while (self.buffer.getLastOrNull()) |last| {
            if (last != ' ' and last != '\t') break;
            self.buffer.pop();
        }
        return self.buffer.items;
    }

    fn next_token(self: *Self) LexError!?data.Token {
        self.buffer.clearRetainingCapacity();
        var token = null;
        self.skipWhiteSpace();

        while (self.ptr.* != '\0') {
            const next_word = try self.readNextWord();

            if (self.containedKeyword()) |keyword| {
                token = switch (keyword) {
                    .text_color => blk: {
                        const color_string = try self.readNextWord();
                        const color = data.Color32.fromHex(color_string);
                        break :blk .{ .text_color = color };
                    },
                    .bg => blk: {
                        const color_string = try self.readNextWord();
                        const color = data.Color32.fromHex(color_string);
                        break :blk .{ .bg = color };
                    },
                    .slide => .slide,
                    .centered => .centered,
                    .left => .left,
                    .right => .right,
                    .text => blk: {
                        _ = self.readUntilNewLine();
                        var text = String.init(std.heap.page_allocator);
                        var line = self.readUntilNewLine();

                        while (line.len != 0) {
                            if (line == "text") break;
                            text.appendSlice(line);
                            text.append('\n');
                            line = self.readUntilNewLine()
                        } else {
                            return LexError.NoClosingKeyword;
                        }
                        break :blk .{ .text = text };
                    },
                    .space => blk: {
                        const int_string = try self.readNextWord();
                        break :blk .{ .space = std.fmt.parseInt(usize, int_string, 10) };
                    },
                    .text_size => blk: {
                        const int_string = try self.readNextWord();
                        break :blk .{ .text_size = std.fmt.parseInt(usize, int_string, 10) };
                    },
                    .image => blk: {
                        const path_slice = try self.readNextWord();
                        var path = String.init(std.heap.page_allocator);
                        path.appendSlice(path_slice);
                        break :blk .{ .image = path };
                    },
                }
                break;
            } else if (next_word.len >= 2 and next_word[0..2] == "//") {
                _ = self.readUntilNewLine();
            } else {
                return LexError.UnknownKeyword;
            }
        }
        return token;
    }
};

pub const SectionData = union {
    lines: usize,
    text: []const u8,
};

pub const SectionType = enum { space, text, image };

pub const ElementAlignment = enum { center, right, left };

pub const Section = struct {
    text_size: usize,
    section_type: SectionType,
    data: SectionData,
    text_color: Color32,
    alignment: ElementAlignment,
};

pub const Slide = struct {
    background_color: Color32,
    sections: ArrayList(Section),
};

pub const SlideShow = struct {
    slides: ArrayList(Slide),
    slide_index: usize = 0,
    title: [:0]const u8,

    const Self = @This();

    pub fn current_slide(self: *Self) *Slide {
        const slide = &(self.slides.items[self.slide_index]);
        return slide;
    }
};

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
    } while (token.type != TOKEN_NONE and token.type != TOKEN_ERROR);

    if (token.type == TOKEN_NONE) {
        Section_array_append(&slide.sections, section);
        Slide_array_append(&slide_show->slides, slide);
    }

    free_string(&lexer.buffer);
    string_table_drop(&lexer.file_aliases);

    if (token.type == TOKEN_ERROR) {
        exit(1);
    }

    if (slide_show->slides.len < 1 or slide_show->slides.len > 999) {
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
    if (c.glfwGetKey(window, c.GLFW_KEY_RIGHT) == c.GLFW_PRESS or c.glfwGetKey(window, c.GLFW_KEY_DOWN) == c.GLFW_PRESS) {
        if (slide_show->current_slide < slide_show->slides.len - 1) {
            slide_show->current_slide++;
        }
    }
    if (c.glfwGetKey(window, c.GLFW_KEY_LEFT) == c.GLFW_PRESS or c.glfwGetKey(window, c.GLFW_KEY_UP) == c.GLFW_PRESS) {
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
