const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
pub const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const data = @import("data.zig");
const c = @import("c.zig");
const win = @import("window.zig");

pub const Keyword = enum(usize) {
    text_color = 0,
    bg = 1,
    slide = 2,
    centered = 3,
    left = 4,
    right = 5,
    text = 6,
    space = 7,
    text_size = 8,
    image = 9,
    image_scale = 10,
    line_spacing = 11,
    font = 12,
    file_drop_image = 13,
};

pub const reserved_names = [_][]const u8{ "text_color", "bg", "slide", "centered", "left", "right", "text", "space", "text_size", "image", "image_scale", "line_spacing", "font", "file_drop_image" };

pub const Token = union(enum) {
    text_color: data.Color32,
    bg: data.Color32,
    slide,
    centered,
    left,
    right,
    text: String,
    space: usize,
    text_size: usize,
    image: String,
    image_scale: f32,
    line_spacing: f64,
    font_style: FontStyle,
    file_drop_image,
};

fn readEntireFile(file_name: []const u8, allocator: Allocator) !String {
    const dir = std.fs.cwd();
    const buffer = try dir.readFileAlloc(allocator, file_name, 4096);
    var string = String.fromOwnedSlice(allocator, buffer);
    try string.append(0); // do this for lexing pointer stuff
    errdefer string.deinit();
    return string;
}

pub const SlidesParseError = error{
    LexerNoClosingKeyword,
    LexerUnknownKeyword,
    LexerInvalidToken,
    EmptySlide,
    TooManySlides,
    InvalidFile,
};

const Lexer = struct {
    file_dir: []const u8, // where the slide show file lives (canonical)
    line: usize = 1,
    buffer: String,
    input: [*:0]const u8,
    ptr: usize = 0,
    allocator: Allocator,

    const Self = @This();

    fn initWithInput(allocator: Allocator, input: []const u8, file_dir: []const u8) !Self {
        return .{
            .file_dir = file_dir,
            .buffer = try String.initCapacity(allocator, input.len), // the buffer is sure to only ever contain the entire input at most, so this enables us to minimize allocations
            .allocator = allocator,
            .input = @ptrCast(input), // null-termination is guarantied
        };
    }

    fn deinit(self: Self) void {
        self.buffer.deinit();
    }

    fn head(self: *const Self) u8 {
        const char = self.input[self.ptr];
        if (char == '\t') return ' '; // we don't want tabs in the final text
        return char;
    }

    fn containedKeyword(self: *Self) ?Keyword {
        for (reserved_names, 0..) |name, i| {
            if (std.mem.eql(u8, self.buffer.items, name)) {
                return @enumFromInt(i);
            }
        }
        return null;
    }

    fn skipWhiteSpace(self: *Self) void {
        while (self.head() == ' ' or self.head() == '\t' or self.head() == '\n') {
            if (self.head() == '\n') self.line += 1;
            self.ptr += 1;
        }
    }

    fn readChar(self: *Self) void {
        self.buffer.appendAssumeCapacity(self.head());
        self.ptr += 1;
    }

    fn readNextWord(self: *Self) []const u8 {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();

        while (self.head() != 0 and self.head() != ' ' and self.head() != '\t' and self.head() != '\n') {
            self.readChar();
        }
        return self.buffer.items;
    }

    fn readUntilNewLine(self: *Self) []const u8 {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();

        while (self.head() != 0 and self.head() != '\n') {
            self.readChar();
        }
        while (self.buffer.getLastOrNull()) |last| {
            if (last != ' ' and last != '\t') break;
            _ = self.buffer.pop().?;
        }
        return self.buffer.items;
    }

    fn nextToken(self: *Self) !?Token {
        self.buffer.clearRetainingCapacity();
        var token: ?Token = null;
        self.skipWhiteSpace();

        while (self.head() != 0) {
            const next_word = self.readNextWord();
            if (next_word.len == 0) break;

            if (self.containedKeyword()) |keyword| {
                token = switch (keyword) {
                    .text_color => blk: {
                        const color_string = self.readNextWord();
                        const parsed_color = data.Color32.fromHex(color_string);
                        if (parsed_color) |color| {
                            break :blk .{ .text_color = color };
                        } else {
                            print("Line {}: '{s}' | ", .{ self.line, color_string });
                            return SlidesParseError.LexerInvalidToken;
                        }
                    },
                    .bg => blk: {
                        const color_string = self.readNextWord();
                        const parsed_color = data.Color32.fromHex(color_string);
                        if (parsed_color) |color| {
                            break :blk .{ .bg = color };
                        } else {
                            print("Line {}: '{s}' | ", .{ self.line, color_string });
                            return SlidesParseError.LexerInvalidToken;
                        }
                    },
                    .slide => .slide,
                    .centered => .centered,
                    .left => .left,
                    .right => .right,
                    .text => blk: {
                        var text = String.init(self.allocator);
                        errdefer text.deinit();
                        var line = self.readUntilNewLine();

                        while (line.len != 0) {
                            if (std.mem.eql(u8, line, "text")) break;
                            try text.appendSlice(line);
                            try text.append('\n');
                            line = self.readUntilNewLine();
                        } else {
                            print("Line {}: ", .{self.line});
                            text.deinit();
                            return SlidesParseError.LexerNoClosingKeyword;
                        }
                        break :blk .{ .text = text };
                    },
                    .space => blk: {
                        const int_string = self.readNextWord();
                        const parsed_int = std.fmt.parseInt(usize, int_string, 10) catch {
                            print("Line {}: '{s}' | ", .{ self.line, int_string });
                            return SlidesParseError.LexerInvalidToken;
                        };
                        break :blk .{ .space = parsed_int };
                    },
                    .text_size => blk: {
                        const int_string = self.readNextWord();
                        const parsed_int = std.fmt.parseInt(usize, int_string, 10) catch {
                            print("Line {}: '{s}' | ", .{ self.line, int_string });
                            return SlidesParseError.LexerInvalidToken;
                        };
                        break :blk .{ .text_size = parsed_int };
                    },
                    .image => blk: {
                        if (self.file_dir.len == 0) return error.ImageInInternalSource;

                        const path_slice = self.readNextWord();
                        var full_image_path = String.init(self.allocator);
                        defer full_image_path.deinit();
                        try full_image_path.appendSlice(self.file_dir);
                        try full_image_path.append('/'); // i think this should be fine on windows
                        try full_image_path.appendSlice(path_slice);
                        const resolved_path = try std.fs.path.resolve(self.allocator, &[_][]const u8{full_image_path.items});
                        const resolved_path_owned = String.fromOwnedSlice(self.allocator, resolved_path);
                        errdefer resolved_path_owned.deinit();
                        std.fs.accessAbsolute(resolved_path_owned.items, .{}) catch |err| {
                            print("Line {}: '{s}' | ", .{ self.line, resolved_path_owned.items });
                            return err;
                        };
                        break :blk .{ .image = resolved_path_owned };
                    },
                    .image_scale => blk: {
                        const scale_slice = self.readNextWord();
                        const parsed_scale = std.fmt.parseFloat(f32, scale_slice) catch {
                            print("Line {}: '{s}' | ", .{ self.line, scale_slice });
                            return SlidesParseError.LexerInvalidToken;
                        };
                        break :blk .{ .image_scale = parsed_scale };
                    },
                    .line_spacing => blk: {
                        const spacing_slice = self.readNextWord();
                        const parsed_spacing = std.fmt.parseFloat(f64, spacing_slice) catch {
                            print("Line {}: '{s}' | ", .{ self.line, spacing_slice });
                            return SlidesParseError.LexerInvalidToken;
                        };
                        break :blk .{ .line_spacing = parsed_spacing };
                    },
                    .font => blk: {
                        const font_slice = self.readNextWord();

                        const font_style: FontStyle = if (std.mem.eql(u8, font_slice, "serif"))
                            .serif
                        else if (std.mem.eql(u8, font_slice, "monospace"))
                            .monospace
                        else
                            return SlidesParseError.LexerInvalidToken;

                        break :blk .{ .font_style = font_style };
                    },
                    .file_drop_image => .file_drop_image,
                };
                break;
            } else if (next_word.len >= 2 and std.mem.eql(u8, next_word[0..2], "//")) {
                _ = self.readUntilNewLine();
            } else {
                print("Line {}: '{s}' | ", .{ self.line, next_word });
                return SlidesParseError.LexerUnknownKeyword;
            }
        }
        return token;
    }
};

pub const ImageSource = union(enum) {
    path: String,
    file_drop_image,
};

pub const SectionType = union(enum) {
    space: usize,
    text: String,
    image: ImageSource,
};

pub const ElementAlignment = enum { center, right, left };

pub const FontStyle = enum { serif, monospace };

pub const Section = struct {
    text_size: usize = 32,
    section_type: SectionType,
    text_color: data.Color32 = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    alignment: ElementAlignment = .left,
    image_scale: f32 = 1.0,
    line_spacing: f64 = 1.0,
    font_style: FontStyle = .serif,
};

pub const Slide = struct {
    background_color: data.Color32 = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    sections: ArrayList(Section),

    const Self = @This();

    fn init(allocator: Allocator) Self {
        return .{ .sections = ArrayList(Section).init(allocator) };
    }
};

pub const SlideShow = struct {
    slides: ArrayList(Slide),
    slide_index: usize = 0,
    tracked_file: String,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return .{
            .slides = ArrayList(Slide).init(allocator),
            .tracked_file = String.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.slides.items) |*slide| {
            for (slide.sections.items) |*section| {
                switch (section.section_type) {
                    .image => |image_source| {
                        switch (image_source) {
                            .path => |path| path.deinit(),
                            .file_drop_image => {},
                        }
                    },
                    .text => |text| text.deinit(),
                    else => {},
                }
            }
            slide.sections.deinit();
        }
        self.slides.deinit();
        self.tracked_file.deinit();
    }

    pub fn loadedFileNameNoExtension(self: *const Self) []const u8 {
        const file_name = self.loadedFileName();

        var i = file_name.len;
        const end = while (i > 0) {
            i -= 1;
            if (file_name[i] == '.') break i;
        } else file_name.len;

        return file_name[0..end];
    }

    fn loadedFileName(self: *const Self) []const u8 {
        return std.fs.path.basename(self.tracked_file.items);
    }

    pub fn loadedFileDir(self: *const Self) []const u8 {
        return std.fs.path.dirname(self.tracked_file.items).?; // the file path is always valid
    }

    pub fn windowTitleAlloc(self: *const Self) !String {
        var title = String.init(self.allocator);
        errdefer title.deinit();
        try title.appendSlice(win.default_title);
        if (self.tracked_file.items.len != 0) {
            try title.appendSlice(" | ");
            try title.appendSlice(self.loadedFileName());
        }
        try title.append(0); // null-termination needed
        return title;
    }

    fn unloadSlides(self: *Self) void {
        for (self.slides.items) |*slide| {
            for (slide.sections.items) |section| {
                switch (section.section_type) {
                    .image => |image_source| {
                        switch (image_source) {
                            .path => |path| path.deinit(),
                            .file_drop_image => {},
                        }
                    },
                    .text => |text| text.deinit(),
                    else => {},
                }
            }
            slide.sections.deinit();
        }
        self.slides.clearRetainingCapacity();
        self.slide_index = 0;
    }

    fn loadSlides(self: *Self, file_path: []const u8) void {
        const file_contents = readEntireFile(file_path, self.allocator) catch |err| {
            print("{s} | Unable to read file: {s}\n", .{ @errorName(err), file_path });
            return;
        };
        defer file_contents.deinit();

        self.parseSlideShow(file_contents.items, true) catch |e| {
            print("Error: {s}", .{@errorName(e)});
            print("\nUnable to parse slide show file: {s}\n", .{file_path});
            return;
        };
        print("Successfully loaded slide show file: '{s}'.\n", .{file_path});
    }

    /// called during hot reloading
    pub fn reloadSlides(self: *Self) void {
        std.debug.assert(self.slides.items.len > 0 and self.tracked_file.items.len > 0); // assumes slides to be tracked
        self.unloadSlides();
        self.loadSlides(self.tracked_file.items);
    }

    pub fn loadNewSlides(self: *Self, file_path: [:0]const u8, window: ?*c.GLFWwindow) !void {
        const full_file_path = try std.fs.realpathAlloc(self.allocator, file_path);
        defer self.allocator.free(full_file_path);

        self.tracked_file.clearRetainingCapacity();
        try self.tracked_file.appendSlice(full_file_path);
        self.unloadSlides();
        self.loadSlides(full_file_path);

        const new_title = try self.windowTitleAlloc();
        defer new_title.deinit();
        c.glfwSetWindowTitle(window, @ptrCast(new_title.items));
    }

    pub fn loadHomeScreenSlide(self: *Self, window: ?*c.GLFWwindow) void {
        const file_tracked = self.tracked_file.items.len > 0;
        if (file_tracked) {
            self.tracked_file.clearRetainingCapacity();
            c.glfwSetWindowTitle(window, win.default_title);
            print("Unloaded slide show file.\n", .{});
        }
        self.unloadSlides();
        self.parseSlideShow(data.home_screen_slide, false) catch |e| {
            print("Error: {s}\n", .{@errorName(e)});
        };
    }

    pub fn currentSlide(self: *const Self) *Slide {
        return &self.slides.items[self.slide_index];
    }

    fn newSlide(self: *Self, slide: *Slide) !void {
        const bg_color = slide.background_color;
        try self.slides.append(slide.*);
        slide.* = Slide.init(self.allocator);
        slide.background_color = bg_color;
    }

    fn parseSlideShow(self: *Self, file_contents: []const u8, file_sourced: bool) !void {
        errdefer self.unloadSlides();

        const slide_file_dir = if (file_sourced) self.loadedFileDir() else "";
        var lexer = try Lexer.initWithInput(self.allocator, file_contents, slide_file_dir);
        defer lexer.deinit();

        var slide = Slide.init(self.allocator);
        errdefer slide.sections.deinit();
        var section = Section{ .section_type = undefined };

        while (try lexer.nextToken()) |token| {
            switch (token) {
                .text_color => |color| {
                    section.text_color = color;
                },
                .bg => |color| {
                    slide.background_color = color;
                },
                .slide => {
                    if (slide.sections.items.len == 0) {
                        print("Line: {} | ", .{lexer.line});
                        return SlidesParseError.EmptySlide;
                    }
                    try self.newSlide(&slide);
                },
                .centered => {
                    section.alignment = .center;
                },
                .left => {
                    section.alignment = .left;
                },
                .right => {
                    section.alignment = .right;
                },
                .text => |string| {
                    section.section_type = .{ .text = string };
                    try newSection(&slide, &section);
                },
                .space => |lines| {
                    section.section_type = .{ .space = lines };
                    try newSection(&slide, &section);
                },
                .text_size => |number| {
                    section.text_size = number;
                },
                .image => |*path| {
                    section.section_type = .{ .image = .{ .path = path.* } };
                    try section.section_type.image.path.append(0); // for c interop later on
                    try newSection(&slide, &section);
                },
                .image_scale => |scale| {
                    section.image_scale = scale;
                },
                .line_spacing => |spacing| {
                    section.line_spacing = spacing;
                },
                .font_style => |style| {
                    section.font_style = style;
                },
                .file_drop_image => {
                    section.section_type = .{ .image = .file_drop_image };
                    try newSection(&slide, &section);
                },
            }
        }

        // create the last slide
        if (slide.sections.items.len == 0) {
            print("Line: {} | ", .{lexer.line});
            return SlidesParseError.EmptySlide;
        }
        try self.slides.append(slide);

        if (self.slides.items.len > 999) return SlidesParseError.TooManySlides;
    }
};

fn newSection(slide: *Slide, section: *Section) !void {
    const text_size = section.text_size;
    const text_color = section.text_color;
    const alignment = section.alignment;
    const image_scale = section.image_scale;
    const line_spacing = section.line_spacing;
    const font_style = section.font_style;

    try slide.sections.append(section.*);

    section.* = Section{ .section_type = undefined };
    section.text_size = text_size;
    section.text_color = text_color;
    section.alignment = alignment;
    section.image_scale = image_scale;
    section.line_spacing = line_spacing;
    section.font_style = font_style;
}
