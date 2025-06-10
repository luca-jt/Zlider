const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
pub const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const data = @import("data.zig");
const c = @import("c.zig");

fn readEntireFile(file_name: []const u8, allocator: Allocator) !String {
    const dir = std.fs.cwd();
    const buffer = try dir.readFileAlloc(allocator, file_name, 4096);
    var string = String.fromOwnedSlice(allocator, buffer);
    try string.append(0); // do this for lexing pointer stuff
    errdefer string.deinit();
    return string;
}

pub const SlidesParseError = error {
    LexerNoKeywordValue,
    LexerNoClosingKeyword,
    LexerUnknownKeyword,
    LexerInvalidToken,
    EmptySlide,
    TooManySlides,
    InvalidFile,
};

const Lexer = struct {
    line: usize = 1,
    buffer: String,
    input: []const u8,
    ptr: usize = 0,
    allocator: Allocator,

    const Self = @This();

    fn initWithInput(allocator: Allocator, input: []const u8) !Self {
        return .{
            .buffer = try String.initCapacity(allocator, input.len), // the buffer is sure to only ever contain the entire input at most, so this enables us to minimize allocations
            .allocator = allocator,
            .input = input,
        };
    }

    fn deinit(self: Self) void {
        self.buffer.deinit();
    }

    fn head(self: *Self) u8 {
        const char = self.input[self.ptr];
        if (char == '\t') return ' '; // we don't want tabs in the final text
        return char;
    }

    fn containedKeyword(self: *Self) ?data.Keyword {
        for (data.reserved_names, 0..) |name, i| {
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

    fn readNextWord(self: *Self) SlidesParseError![]const u8 {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();

        while (self.head() != 0 and self.head() != ' ' and self.head() != '\t' and self.head() != '\n') {
            self.readChar();
        }
        if (self.buffer.items.len == 0) {
            print("Line: {} | ", .{self.line});
            return SlidesParseError.LexerNoKeywordValue;
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

    fn nextToken(self: *Self) !?data.Token {
        self.buffer.clearRetainingCapacity();
        var token: ?data.Token = null;
        self.skipWhiteSpace();

        while (self.head() != 0) {
            const next_word = try self.readNextWord();

            if (self.containedKeyword()) |keyword| {
                token = switch (keyword) {
                    .text_color => blk: {
                        const color_string = try self.readNextWord();
                        const parsed_color = data.Color32.fromHex(color_string);
                        if (parsed_color) |color| {
                            break :blk .{ .text_color = color };
                        } else {
                            print("Line {}: '{s}' | ", .{self.line, color_string});
                            return SlidesParseError.LexerInvalidToken;
                        }
                    },
                    .bg => blk: {
                        const color_string = try self.readNextWord();
                        const parsed_color = data.Color32.fromHex(color_string);
                        if (parsed_color) |color| {
                            break :blk .{ .bg = color };
                        } else {
                            print("Line {}: '{s}' | ", .{self.line, color_string});
                            return SlidesParseError.LexerInvalidToken;
                        }
                    },
                    .slide => .slide,
                    .centered => .centered,
                    .left => .left,
                    .right => .right,
                    .text => blk: {
                        _ = self.readUntilNewLine();
                        var text = String.init(self.allocator);
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
                        const int_string = try self.readNextWord();
                        const parsed_int = std.fmt.parseInt(usize, int_string, 10) catch {
                            print("Line {}: '{s}' | ", .{self.line, int_string});
                            return SlidesParseError.LexerInvalidToken;
                        };
                        break :blk .{ .space = parsed_int };
                    },
                    .text_size => blk: {
                        const int_string = try self.readNextWord();
                        const parsed_int = std.fmt.parseInt(usize, int_string, 10) catch {
                            print("Line {}: '{s}' | ", .{self.line, int_string});
                            return SlidesParseError.LexerInvalidToken;
                        };
                        break :blk .{ .text_size = parsed_int };
                    },
                    .image => blk: {
                        const path_slice = try self.readNextWord();
                        std.fs.cwd().access(path_slice, .{}) catch |err| {
                            print("Line {}: '{s}' | ", .{self.line, path_slice});
                            return err;
                        };
                        var path = String.init(self.allocator);
                        try path.appendSlice(path_slice);
                        break :blk .{ .image = path };
                    },
                };
                break;
            } else if (next_word.len >= 2 and std.mem.eql(u8, next_word[0..2], "//")) {
                _ = self.readUntilNewLine();
            } else {
                print("Line {}: '{s}' | ", .{self.line, next_word});
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
    title: String, // this string always contains a null-terminated sequence of bytes due to the data source
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var self = Self{
            .slides = ArrayList(Slide).init(allocator),
            .title = String.init(allocator),
            .allocator = allocator,
        };
        try self.title.appendSlice("Zlider");
        try self.title.append(0); // null-termination is needed
        return self;
    }

    pub fn deinit(self: Self) void {
        for (self.slides.items) |*slide| {
            for (slide.sections.items) |*section| {
                switch (section.section_type) {
                    .image, .text => section.data.text.deinit(),
                    else => {},
                }
            }
            slide.sections.deinit();
        }
        self.slides.deinit();
        self.title.deinit();
    }

    pub fn titleSlice(self: *Self) []const u8 {
        return self.title.items[0..self.title.items.len - 1];
    }

    pub fn titleSentinelSlice(self: *Self) [:0]const u8 {
        return self.title.items[0..self.title.items.len - 1 :0];
    }

    /// returns wether or not slides were present
    pub fn unloadSlides(self: *Self) !bool {
        if (self.slides.items.len == 0) return false;

        for (self.slides.items) |*slide| {
            for (slide.sections.items) |section| {
                switch (section.section_type) {
                    .image, .text => section.data.text.deinit(),
                    else => {},
                }
            }
            slide.sections.deinit();
        }
        self.slides.clearRetainingCapacity();

        self.title.clearRetainingCapacity();
        try self.title.appendSlice("Zlider");

        return true;
    }

    pub fn loadSlides(self: *Self, file_path: [:0]const u8, window: ?*c.GLFWwindow) !void {
        const full_file_path = try std.fs.realpathAlloc(self.allocator, file_path);
        defer self.allocator.free(full_file_path);

        const file_contents = readEntireFile(full_file_path, self.allocator) catch |err| {
            print("{s} | Unable to read file: {s}\n", .{@errorName(err), full_file_path});
            return;
        };
        defer file_contents.deinit();

        self.parseSlideShow(&file_contents) catch |e| {
            print("Error: {s}", .{@errorName(e)});
            print("\nUnable to parse slide show file: {s}\n", .{full_file_path});
            return;
        };

        std.debug.assert(try self.unloadSlides()); // already resets the title

        try self.title.appendSlice(" | ");
        try self.title.appendSlice(full_file_path);
        try self.title.append(0); // null-termination is needed
        c.glfwSetWindowTitle(window, self.titleSentinelSlice());
        print("Successfully loaded slide show file: '{s}'.\n", .{full_file_path});
    }

    pub fn currentSlide(self: *Self) ?*Slide {
        return if (self.slides.items.len == 0)
            null
        else
            &(self.slides.items[self.slide_index]);
    }

    fn newSlide(self: *Self, slide: *Slide, section: *Section) !void {
        try newSection(slide, section);
        const bg_color = slide.background_color;
        try self.slides.append(slide.*);
        slide.* = Slide.init(self.allocator);
        slide.background_color = bg_color;
    }

    fn parseSlideShow(self: *Self, file_contents: *const String) !void {
        var lexer = try Lexer.initWithInput(self.allocator, file_contents.items);
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
                    if (slide.sections.items.len == 0 and !section_has_data) {
                        print("Line: {} | ", .{lexer.line});
                        return SlidesParseError.EmptySlide;
                    }
                    try self.newSlide(&slide, &section);
                    section_has_data = false;
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
                    if (self.slides.items.len != 0 or slide.sections.items.len != 0) {
                        // skip the first section append
                        try newSection(&slide, &section);
                    }
                    section.section_type = .text;
                    section.data = .{ .text = string };
                    section_has_data = true;
                },
                .space => |number| {
                    if (self.slides.items.len != 0 or slide.sections.items.len != 0) {
                        // skip the first section append
                        try newSection(&slide, &section);
                    }
                    section.section_type = .space;
                    section.data = .{ .lines = number };
                    section_has_data = true;
                },
                .text_size => |number| {
                    section.text_size = number;
                },
                .image => |path| {
                    if (self.slides.items.len != 0 or slide.sections.items.len != 0) {
                        // skip the first section append
                        try newSection(&slide, &section);
                    }
                    section.section_type = .image;
                    section.data = .{ .text = path };
                    try section.data.text.append(0); // for c interop later on
                    section_has_data = true;
                },
            }
        }

        // create the last slide
        if (slide.sections.items.len == 0 and !section_has_data) {
            print("Line: {} | ", .{lexer.line});
            return SlidesParseError.EmptySlide;
        }
        try newSection(&slide, &section);
        try self.slides.append(slide);
        section_has_data = false;

        if (self.slides.items.len > 999) return SlidesParseError.TooManySlides;
    }
};

fn newSection(slide: *Slide, section: *Section) !void {
    const text_size = section.text_size;
    const text_color = section.text_color;
    const alignment = section.alignment;

    try slide.sections.append(section.*);

    section.* = Section{ .section_type = undefined, .data = undefined };
    section.text_size = text_size;
    section.text_color = text_color;
    section.alignment = alignment;
}
