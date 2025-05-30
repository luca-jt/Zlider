const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
pub const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const HashMap = std.AutoHashMap;
const data = @import("data.zig");
const Renderer = @import("rendering.zig").Renderer;
const window_state = @import("window.zig").window_state;

fn readEntireFile(file_name: []const u8, allocator: Allocator) !String {
    const dir = std.fs.cwd();
    const buffer = try dir.readFileAlloc(allocator, file_name, 4096);
    var string = String.fromOwnedSlice(allocator, buffer);
    string.append('\0'); // do this for lexing pointer stuff
    return string;
}

pub const SlidesParseError = error {
    LexerNoKeywordValue,
    LexerNoClosingKeyword,
    LexerUnknownKeyword,
    ParserEmptySlide,
    TooManySlides,
};

const Lexer = struct {
    line: usize = 0,
    buffer: String,
    ptr: *const u8,
    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator, ptr: *const u8) Self {
        return .{
            .buffer = String.init(allocator),
            .allocator = allocator,
            .ptr: ptr,
        };
    }

    fn deinit(self: Self) void {
        self.buffer.deinit();
    }

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

    fn readNextWord(self: *Self) SlidesParseError![]const u8 {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();

        while (self.ptr.* != '\0' and self.ptr.* != ' ' and self.ptr.* != '\t' and self.ptr.* != '\n') {
            self.readChar();
        }
        if (self.buffer.len == 0) {
            print("Line: {} | ", self.line);
            return SlidesParseError.LexerNoKeywordValue;
        }
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

    fn nextToken(self: *Self) SlidesParseError!?data.Token {
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
                            print("Line: {} | ", self.line);
                            return SlidesParseError.LexerNoClosingKeyword;
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
                print("Line: {} | ", self.line);
                return SlidesParseError.LexerUnknownKeyword;
            }
        }
        return token;
    }
};

pub const SectionData = union {
    lines: usize,
    text: String,
};

pub const SectionType = enum { space, text, image };

pub const ElementAlignment = enum { center, right, left };

pub const Section = struct {
    text_size: usize = 12,
    section_type: SectionType,
    data: SectionData,
    text_color: data.Color32 = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    alignment: ElementAlignment = .left,
};

pub const Slide = struct {
    background_color: Color32 = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    sections: ArrayList(Section),

    const Self = @This();

    fn init(allocator: Allocator) Self {
        return .{ .sections = ArrayList(Section).init(self.allocator) };
    }
};

pub const SlideShow = struct {
    slides: ArrayList(Slide),
    slide_index: usize = 0,
    title: [:0]const u8 = "Zlider",
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .slides = ArrayList(Slide).init(allocator),
            .allocator = allocator,
        }
    }

    pub fn deinit(self: Self) void {
        for (&self.slides) |*slide| {
            for (&slide.sections) |section| {
                switch (section.section_type) {
                    .image, .text => section.data.text.deinit();
                    else => {},
                }
            }
            slide.sections.deinit();
        }
        self.slides.deinit();
    }

    pub fn loadSlides(self: *Self, file_path: [:0]const u8) void {
        const file_contents = readEntireFile(file_path) catch {
            print("Unable to read file: {}\n", file_path);
            return;
        };
        defer file_contents.deinit();

        self.title = file_path;

        for (&self.slides) |*slide| {
            for (&slide.sections) |section| {
                switch (section.section_type) {
                    .image, .text => section.data.text.deinit();
                    else => {},
                }
            }
            slide.sections.deinit();
        }
        self.slides.clearRetainingCapacity();

        try self.parseSlideShow(file_contents) catch |e| {
            switch (e) {
                .LexerNoKeywordValue => { print("Lexer Error: missing keyword"); },
                .LexerNoClosingKeyword => { print("Lexer Error: no closing keyword"); },
                .LexerUnknownKeyword => { print("Lexer Error: unknown keyword"); },
                .ParserEmptySlide => { print("Parser Error: missing keyword"); },
                .TooManySlides => { print("Parser Error: missing keyword"); },
            }
            print("\nUnable to parse slide show file: {}\n", file_path);
        };
    }

    pub fn currentSlide(self: *Self) *Slide {
        const slide = &(self.slides.items[self.slide_index]);
        return slide;
    }

    fn newSlide(self: *Self, slide: *Slide, section: *Section) void {
        newSection(slide, section);
        const bg_color = slide.background_color;
        self.slides.append(slide.*);
        slide.* = Slide.init(self.allocator);
        slide.background_color = bg_color;
    }

    fn parseSlideShow(self: *Self, file_contents: *String) SlidesParseError!void {
        var lexer = Lexer.init(self.allocator, &file_contents.items[0]);
        defer lexer.deinit();

        var slide = Slide.init(self.allocator);
        defer slide.sections.deinit();
        var section = Section{ .section_type = undefined, .data = undefined };
        var section_has_data = false;

        while (try lexer.nextToken()) |token| {
            switch (token) {
                .text_color => |color| {
                    section.text_color = color;
                },
                .bg => |color| {
                    slide.background_color = color;
                },
                .slide => {
                    if (slide.sections.len == 0 and !section_has_data) {
                        print("Line: {} | ", lexer.line);
                        return SlidesParseError.ParserEmptySlide;
                    }
                    self.newSlide(&slide, &section);
                    section_has_data = false;
                },
                .centered => {
                    section.alignment = .centered;
                },
                .left => {
                    section.alignment = .left;
                },
                .right => {
                    section.alignment = .right;
                },
                .text => |string| {
                    if (self.slides.len != 0 or slide.sections.len != 0) {
                        // skip the first section append
                        newSection(&slide, &section);
                    }
                    section.section_type = .text;
                    section.data = .{ .text = string };
                    section_has_data = true;
                },
                .space => |number| {
                    if (self.slides.len != 0 or slide.sections.len != 0) {
                        // skip the first section append
                        newSection(&slide, &section);
                    }
                    section.section_type = .space;
                    section.data = .{ .lines = number };
                    section_has_data = true;
                },
                .text_size => |number| {
                    section.text_size = number;
                },
                .image => |path| {
                    if (self.slides.len != 0 or slide.sections.len != 0) {
                        // skip the first section append
                        newSection(&slide, &section);
                    }
                    section.section_type = .image;
                    section.data = .{ .text = path };
                    section.data.text.append('\0'); // for c interop later on
                    section_has_data = true;
                },
            }
        }

        // create the last slide
        if (slide.sections.len == 0 and !section_has_data) {
            print("Line: {} | ", lexer.line);
            return SlidesParseError.ParserEmptySlide;
        }
        newSection(&slide, &section);
        self.slides.append(slide);
        section_has_data = false;

        if (self.slides.len > 999) return SlidesParseError.TooManySlides;
    }
};

fn newSection(slide: *Slide, section: *Section) void {
    const text_size = section.text_size;
    const text_color = section.text_color;
    const alignment = section.alignment;

    slide.sections.append(section.*);

    section.* = Section{ .section_type = undefined, .data = undefined };
    section.text_size = text_size;
    section.text_color = text_color;
    section.alignment = alignment;
}

pub fn handle_input(window: *c.GLFWwindow, slide_show: *SlideShow, renderer: *Renderer) !void {
    // fullscreen toggle
    if (c.glfwGetKey(window, c.GLFW_KEY_F11) == c.GLFW_PRESS) {
        const monitor = c.glfwGetPrimaryMonitor();
        if (!c.glfwGetWindowMonitor(window)) {
            update_window_attributes(window);
            const mode = c.glfwGetVideoMode(monitor);
            c.glfwSetWindowMonitor(window, monitor, 0, 0, mode.width, mode.height, c.GLFW_DONT_CARE);
        } else {
            c.glfwSetWindowMonitor(window, null, window_state.win_pos_x, window_state.win_pos_y, window_state.win_size_x, window_state.win_size_y, c.GLFW_DONT_CARE);
        }
    }
    // slide_show_switch
    if (c.glfwGetKey(window, c.GLFW_KEY_RIGHT) == c.GLFW_PRESS or c.glfwGetKey(window, c.GLFW_KEY_DOWN) == c.GLFW_PRESS) {
        if (slide_show.slide_index < slide_show.slides.len - 1) {
            slide_show.slide_index += 1;
        }
    }
    if (c.glfwGetKey(window, c.GLFW_KEY_LEFT) == c.GLFW_PRESS or c.glfwGetKey(window, c.GLFW_KEY_UP) == c.GLFW_PRESS) {
        if (slide_show.slide_index > 0) {
            slide_show.slide_index -= 1;
        }
    }
    // dump the slides to png
    if (c.glfwGetKey(window, c.GLFW_KEY_I) == c.GLFW_PRESS) {
        const current_slide_idx = slide_show.slide_index;
        slide_show.slide_index = 0;

        const slide_mem_size: usize = @intCast(window_state.vp_size_x) * @intCast(window_state.vp_size_y) * 4;
        const slide_mem = try std.heap.page_allocator.allocSentinel(u8, slide_mem_size, 0);
        defer std.heap.page_allocator.free(slide_mem);

        const compression_level = 5;

        var slide_file_name = String.init(std.heap.page_allocator);
        defer slide_file_name.deinit();
        slide_file_name.appendSlice(slide_show.title);
        slide_file_name.appendSlice("_000\0");

        var number_slice = slide_file_name.items[slide_file_name.len-4..slide_file_name.len-1];

        while (slide_show.slide_index < slide_show.slides.len) {
            const slide_number = slide_show.slide_index + 1;
            _ = std.fmt.bufPrintIntToSlice(number_slice, slide_number, 10, .lower, .{ .width = 3, .fill = '0' });

            renderer.render(slide_show);
            copy_frame_buffer_to_memory(slide_mem);

            c.stbi_write_png(slide_file_name.items, window_state.vp_size_x, window_state.vp_size_y, compression_level, slide_mem, 4);
            slide_show.slide_index += 1;
        }

        slide_show.slide_index = current_slide_idx;
    }
    // load new file on drag and drop
    if (true) {
        // TODO: here the slides and the renderer must be cleaned up first
        //slide_show.loadSlides(file_path);
        //renderer.loadSlideData(&slide_show);
    }
}
