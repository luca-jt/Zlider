const std = @import("std");
const assert = std.debug.assert;
pub const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const data = @import("data.zig");
const c = @import("c.zig");
const win = @import("window.zig");
const state = @import("state.zig");

pub const Keyword = enum(usize) {
    text_color,
    bg,
    slide,
    center,
    left,
    right,
    text,
    space,
    text_size,
    image,
    line_spacing,
    font,
    file_drop_image,
    aspect_ratio,
    black_bars,
    header,
    footer,
    no_header,
    no_footer,
    quad,
    left_space,
    right_space,
};

pub const Token = union(enum) {
    text_color: data.Color32,
    bg: data.Color32,
    slide: bool, // wether or not the slide is a fallthrough slide
    center,
    left,
    right,
    text: String,
    space: usize,
    text_size: usize,
    image: Image,
    line_spacing: f64,
    font_style: FontStyle,
    file_drop_image: f32, // scale
    aspect_ratio: f32,
    black_bars: bool,
    header,
    footer,
    no_header,
    no_footer,
    quad: ColorQuad,
    left_space: f64,
    right_space: f64,
};

const Lexer = struct {
    file_dir: ?[]const u8, // where the slide show file lives (canonical)
    line: usize = 1,
    buffer: String,
    input: [*:0]const u8,
    ptr: usize = 0,

    const Self = @This();

    fn initWithInput(input: []const u8, file_dir: ?[]const u8) !Self {
        return .{
            .file_dir = file_dir,
            .buffer = try String.initCapacity(state.allocator, input.len), // the buffer is sure to only ever contain the entire input at most, so this enables us to minimize allocations
            .input = @ptrCast(input), // null-termination is guarantied
        };
    }

    fn deinit(self: Self) void {
        self.buffer.deinit();
    }

    fn head(self: *const Self) u8 {
        const char = self.input[self.ptr];
        if (char == '\t') return ' '; // we don't want tabs in the final text and replace them with single spaces
        return char;
    }

    fn contents(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    fn containedKeyword(self: *Self) ?Keyword {
        inline for (@typeInfo(Keyword).@"enum".fields) |field| {
            if (std.mem.eql(u8, self.contents(), field.name)) {
                return @enumFromInt(field.value);
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

    fn readNextWord(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();

        while (self.head() != 0 and self.head() != ' ' and self.head() != '\t' and self.head() != '\n') {
            self.readChar();
        }
    }

    fn peekNextWord(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.skipWhiteSpace();
        const old_ptr = self.ptr;

        while (self.head() != 0 and self.head() != ' ' and self.head() != '\t' and self.head() != '\n') {
            self.readChar();
        }
        self.ptr = old_ptr;
    }

    fn readUntilNewLine(self: *Self) void {
        self.buffer.clearRetainingCapacity();

        while (self.head() != 0 and self.head() != '\n') {
            self.readChar();
        }
        while (self.buffer.getLastOrNull()) |last| {
            if (last != ' ' and last != '\t') break;
            _ = self.buffer.pop().?;
        }
        if (self.head() == '\n') {
            self.ptr += 1; // skip the one newline
            self.line += 1;
        }
    }

    fn readNextParameter(self: *Self, comptime T: type) !T {
        const opt_param = self.readNextOptionalParameter(T);
        if (opt_param) |param| return param;
        std.log.err("Line {}: '{s}' | Lexer interupt", .{ self.line, self.contents() });
        return error.InvalidToken;
    }

    fn readNextOptionalParameter(self: *Self, comptime T: type) ?T {
        self.peekNextWord();
        const param = switch (T) {
            data.Color32 => data.Color32.fromHex(self.contents()),
            usize, u8 => if (std.fmt.parseInt(T, self.contents(), 10)) |parsed_int| parsed_int else |_| null,
            f64, f32 => if (std.fmt.parseFloat(T, self.contents())) |parsed_float| parsed_float else |_| null,
            bool => if (std.mem.eql(u8, self.contents(), "true")) true else if (std.mem.eql(u8, self.contents(), "false")) false else null,
            else => @compileError("unsupported lexer parameter type"),
        };
        if (param != null) self.readNextWord();
        return param;
    }

    fn nextToken(self: *Self) !?Token {
        self.buffer.clearRetainingCapacity();
        var token: ?Token = null;
        self.skipWhiteSpace();

        while (self.head() != 0) {
            self.readNextWord();
            if (self.contents().len == 0) break;

            if (self.containedKeyword()) |keyword| {
                token = switch (keyword) {
                    .text_color => .{ .text_color = try self.readNextParameter(data.Color32) },
                    .bg => .{ .bg = try self.readNextParameter(data.Color32) },
                    .slide => blk: {
                        self.peekNextWord();
                        const is_fallthrough = std.mem.eql(u8, self.contents(), "fallthrough");
                        if (is_fallthrough) self.readNextWord();
                        break :blk .{ .slide = is_fallthrough };
                    },
                    .center => .center,
                    .left => .left,
                    .right => .right,
                    .text => blk: {
                        var text = String.init(state.allocator);
                        errdefer text.deinit();
                        if (self.head() == '\n') {
                            self.ptr += 1; // skip the newline after the keyword
                            self.line += 1;
                        }
                        self.readUntilNewLine();
                        // This loop runs until the end of the file is found. In case the last word in the file is 'text' we also have to check for the line length to make shure to register it.
                        while (self.head() != 0 or self.contents().len != 0) {
                            if (std.mem.eql(u8, self.contents(), "text")) break;
                            if (self.contents().len != 0) try text.appendSlice(self.contents());
                            try text.append('\n');
                            self.readUntilNewLine();
                        } else {
                            std.log.err("Line {}: 'text' | Lexer interupt", .{self.line});
                            return error.NoClosingKeyword;
                        }
                        _ = text.pop(); // remove the trailing line break if present

                        break :blk .{ .text = text };
                    },
                    .space => .{ .space = try self.readNextParameter(usize) },
                    .text_size => .{ .text_size = try self.readNextParameter(usize) },
                    .image => blk: {
                        if (self.file_dir == null) {
                            std.log.err("Line {} | Lexer interupt", .{ self.line });
                            return error.ImageInInternalSource;
                        }

                        self.readNextWord();
                        var full_image_path = String.init(state.allocator);
                        defer full_image_path.deinit();
                        try full_image_path.appendSlice(self.file_dir.?);
                        try full_image_path.append('/'); // i think this should be fine on windows
                        try full_image_path.appendSlice(self.contents());
                        const resolved_path = try std.fs.path.resolve(state.allocator, &[_][]const u8{full_image_path.items});
                        const resolved_path_owned = String.fromOwnedSlice(state.allocator, resolved_path);
                        errdefer resolved_path_owned.deinit();
                        std.fs.accessAbsolute(resolved_path_owned.items, .{}) catch |err| {
                            std.log.err("Line {}: '{s}' | Lexer interupt", .{ self.line, resolved_path_owned.items });
                            return err;
                        };

                        const scale = if (self.readNextOptionalParameter(f32)) |s| s else 1.0;

                        break :blk .{ .image = .{ .path = resolved_path_owned, .scale = scale } };
                    },
                    .line_spacing => .{ .line_spacing = try self.readNextParameter(f64) },
                    .font => blk: {
                        self.readNextWord();

                        const font_style: FontStyle = if (std.mem.eql(u8, self.contents(), "serif"))
                            .serif
                        else if (std.mem.eql(u8, self.contents(), "sans_serif"))
                            .sans_serif
                        else if (std.mem.eql(u8, self.contents(), "monospace"))
                            .monospace
                        else
                            return error.InvalidToken;

                        break :blk .{ .font_style = font_style };
                    },
                    .file_drop_image => blk: {
                        const scale = if (self.readNextOptionalParameter(f32)) |s| s else 1.0;
                        break :blk .{ .file_drop_image = scale };
                    },
                    .aspect_ratio => blk: {
                        const width = try self.readNextParameter(u8);
                        const height = try self.readNextParameter(u8);
                        const ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
                        break :blk .{ .aspect_ratio = ratio };
                    },
                    .black_bars => .{ .black_bars = try self.readNextParameter(bool) },
                    .header => .header,
                    .footer => .footer,
                    .no_header => .no_header,
                    .no_footer => .no_footer,
                    .quad => blk: {
                        const color = try self.readNextParameter(data.Color32);
                        const width = try self.readNextParameter(f32);
                        const height = try self.readNextParameter(f32);
                        break :blk .{ .quad = .{ .color = color, .width = width, .height = height } };
                    },
                    .left_space => .{ .left_space = try self.readNextParameter(f64) },
                    .right_space => .{ .right_space = try self.readNextParameter(f64) },
                };
                break;
            } else if (self.contents().len >= 2 and std.mem.eql(u8, self.contents()[0..2], "//")) {
                self.readUntilNewLine();
            } else {
                std.log.err("Line {}: '{s}' | Lexer interupt", .{ self.line, self.contents() });
                return error.UnknownKeyword;
            }
        }
        return token;
    }
};

pub const ImageSource = union(enum) {
    image: Image,
    file_drop_image: f32, // scale

    const Self = @This();

    fn clone(self: Self) !Self {
        switch (self) {
            .image => |image| return .{ .image = try image.clone() },
            .file_drop_image => return self,
        }
    }

    pub fn scale(self: Self) f32 {
        switch (self) {
            .image => |image| return image.scale,
            .file_drop_image => |s| return s,
        }
    }
};

pub const Image = struct {
    path: String,
    scale: f32,

    const Self = @This();

    fn clone(self: *const Self) !Self {
        var copy = self.*;
        copy.path = try self.path.clone();
        return copy;
    }

    fn deinit(self: Self) void {
        self.path.deinit();
    }
};

pub const ColorQuad = struct {
    color: data.Color32,
    width: f32,
    height: f32,
};

pub const SectionType = union(enum) {
    space: usize,
    text: String,
    image_source: ImageSource,
    quad: ColorQuad,
};

pub const ElementAlignment = enum { center, right, left };

pub const FontStyle = enum { serif, sans_serif, monospace };

pub const Section = struct {
    text_size: usize = 40,
    section_type: SectionType,
    text_color: data.Color32 = @bitCast(@as(u32, 0x000000FF)),
    alignment: ElementAlignment = .left,
    line_spacing: f64 = 1.0,
    font_style: FontStyle = .serif,
    left_space: f64 = 10,
    right_space: f64 = 10,

    const Self = @This();

    fn clone(self: *const Self) !Section {
        var copy = self.*;
        switch (copy.section_type) {
            .text => |*text| {
                text.* = try text.clone();
            },
            .image_source => |*image_source| {
                image_source.* = try image_source.clone();
            },
            .space, .quad => {},
        }
        return copy;
    }

    fn deinit(self: Self) void {
        switch (self.section_type) {
            .image_source => |image_source| {
                switch (image_source) {
                    .image => |image| image.deinit(),
                    .file_drop_image => {},
                }
            },
            .text => |text| text.deinit(),
            else => {},
        }
    }
};

pub const Slide = struct {
    background_color: data.Color32 = @bitCast(@as(u32, 0xFFFFFFFF)),
    has_fallthrough_successor: bool = false,
    exclude_header: bool = false,
    exclude_footer: bool = false,
    sections: ArrayList(Section),

    const Self = @This();

    fn init() Self {
        return .{ .sections = ArrayList(Section).init(state.allocator) };
    }

    fn clone(self: *const Self) !Slide {
        var copy = self.*;
        copy.sections = try self.sections.clone();
        for (copy.sections.items) |*section| {
            section.* = try section.clone();
        }
        return copy;
    }

    fn deinit(self: Self) void {
        for (self.sections.items) |*section| {
            section.deinit();
        }
        self.sections.deinit();
    }
};

fn watchCallback(watch_id: c.dmon_watch_id, action: c.dmon_action, root_dir: [*c]const u8, file_path: [*c]const u8, old_file_path: [*c]const u8, user: ?*anyopaque) callconv(.c) void {
    _ = watch_id;
    _ = root_dir;
    _ = old_file_path;
    _ = user;

    //
    // This function is called in a seperate thread. All the actions below are read-only or atomic.
    // There should not be a concurrent state mutating operation that messes with this.
    // I might be wrong though and we might have to come back to this.
    //

    assert(state.slide_show.fileIsTracked());

    const is_slide_show_file = std.mem.eql(u8, state.slide_show.loadedFileName(), std.mem.span(file_path));
    const should_reload = (action == c.DMON_ACTION_MODIFY and is_slide_show_file);

    if (should_reload) {
        @atomicStore(bool, &state.file_watcher_modify_message, true, std.builtin.AtomicOrder.release);
        c.glfwPostEmptyEvent();
    }
}

pub const SlideShow = struct {
    slides: ArrayList(Slide),
    header: ArrayList(Section),
    footer: ArrayList(Section),
    slide_index: usize = 0,
    tracked_file: String,
    watched_dir_id: ?c.dmon_watch_id = null,

    const Self = @This();

    pub fn init() !Self {
        c.dmon_init();
        return .{
            .slides = ArrayList(Slide).init(state.allocator),
            .header = ArrayList(Section).init(state.allocator),
            .footer = ArrayList(Section).init(state.allocator),
            .tracked_file = String.init(state.allocator),
        };
    }

    pub fn deinit(self: Self) void {
        for (self.slides.items) |*slide| {
            slide.deinit();
        }
        self.slides.deinit();

        for (self.header.items) |*section| {
            section.deinit();
        }
        self.header.deinit();

        for (self.footer.items) |*section| {
            section.deinit();
        }
        self.footer.deinit();

        self.tracked_file.deinit();
        c.dmon_deinit();
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

    pub fn fileIsTracked(self: *const Self) bool {
        return self.tracked_file.items.len > 0; // when tracking stops, the buffer is cleared
    }

    fn unloadSlides(self: *Self) void {
        for (self.header.items) |*section| {
            section.deinit();
        }
        self.header.clearRetainingCapacity();

        for (self.footer.items) |*section| {
            section.deinit();
        }
        self.footer.clearRetainingCapacity();

        for (self.slides.items) |*slide| {
            slide.deinit();
        }
        self.slides.clearRetainingCapacity();
        self.slide_index = 0;
    }

    pub fn currentSlide(self: *const Self) ?*Slide {
        return if (self.containsSlides()) &self.slides.items[self.slide_index] else null;
    }

    pub fn containsSlides(self: *const Self) bool {
        return self.slides.items.len > 0;
    }

    fn newSlide(self: *Self, slide: *Slide, is_fallthrough: bool) !void {
        if (is_fallthrough) {
            const slide_clone = try slide.clone();
            slide.has_fallthrough_successor = true;
            try self.slides.append(slide.*);
            slide.* = slide_clone;
        } else {
            try self.slides.append(slide.*);
            const bg_color = slide.background_color;
            slide.* = Slide.init();
            slide.background_color = bg_color;
        }
    }
};

const SectionLocation = union(enum) {
    slide: *Slide,
    marginal: *ArrayList(Section), // header/footer
};

fn addSection(location: SectionLocation, section: *Section) !void {
    switch (location) {
        .slide => |slide| try slide.sections.append(section.*),
        .marginal => |marginal| try marginal.append(section.*),
    }
    section.section_type = undefined;
}

fn parseSlideShow(file_contents: []const u8) !void {
    errdefer unloadSlideShow();

    const slide_file_dir = if (state.slide_show.fileIsTracked()) state.slide_show.loadedFileDir() else null;
    var lexer = try Lexer.initWithInput(file_contents, slide_file_dir);
    defer lexer.deinit();

    var slide = Slide.init();
    errdefer slide.sections.deinit();
    var section = Section{ .section_type = undefined };
    var header_defined = false;
    var footer_defined = false;

    while (try lexer.nextToken()) |token| {
        switch (token) {
            .text_color => |color| {
                section.text_color = color;
            },
            .bg => |color| {
                if (header_defined or footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.BackgroundColorInMarginal;
                }
                slide.background_color = color;
            },
            .slide => |is_fallthrough| {
                if (header_defined or footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.SlideAfterMarginalDefinition;
                }
                try state.slide_show.newSlide(&slide, is_fallthrough);
            },
            .center => {
                section.alignment = .center;
            },
            .left => {
                section.alignment = .left;
            },
            .right => {
                section.alignment = .right;
            },
            .text => |string| {
                const location: SectionLocation = if (footer_defined)
                    .{ .marginal = &state.slide_show.footer }
                else if (header_defined)
                    .{ .marginal = &state.slide_show.header }
                else
                    .{ .slide = &slide };

                section.section_type = .{ .text = string };
                try addSection(location, &section);
            },
            .space => |lines| {
                const location: SectionLocation = if (footer_defined)
                    .{ .marginal = &state.slide_show.footer }
                else if (header_defined)
                    .{ .marginal = &state.slide_show.header }
                else
                    .{ .slide = &slide };

                section.section_type = .{ .space = lines };
                try addSection(location, &section);
            },
            .text_size => |number| {
                section.text_size = number;
            },
            .image => |*image| {
                const location: SectionLocation = if (footer_defined)
                    .{ .marginal = &state.slide_show.footer }
                else if (header_defined)
                    .{ .marginal = &state.slide_show.header }
                else
                    .{ .slide = &slide };

                section.section_type = .{ .image_source = .{ .image = image.* } };
                try section.section_type.image_source.image.path.append(0); // for c interop later on
                try addSection(location, &section);
            },
            .line_spacing => |spacing| {
                section.line_spacing = spacing;
            },
            .font_style => |style| {
                section.font_style = style;
            },
            .file_drop_image => |scale| {
                const location: SectionLocation = if (footer_defined)
                    .{ .marginal = &state.slide_show.footer }
                else if (header_defined)
                    .{ .marginal = &state.slide_show.header }
                else
                    .{ .slide = &slide };

                section.section_type = .{ .image_source = .{ .file_drop_image = scale } };
                try addSection(location, &section);
            },
            .aspect_ratio => |ratio| {
                if (header_defined or footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.AspectRatioInMarginal;
                }
                state.window.forceViewportAspectRatio(ratio);
                state.window.updateViewport(state.window.size_x, state.window.size_y);
                state.renderer.updateMatrices();
            },
            .black_bars => |flag| {
                if (header_defined or footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.BlackBarsInMarginal;
                }
                state.window.display_black_bars = flag;
                state.window.updateViewport(state.window.size_x, state.window.size_y);
            },
            .header => {
                if (header_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.MultipleHeaders;
                }
                if (footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.HeaderDefinitionAfterFooter;
                }
                header_defined = true;
                section = Section{ .section_type = undefined };
            },
            .footer => {
                if (footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.MultipleFooters;
                }
                footer_defined = true;
                if (!header_defined) section = Section{ .section_type = undefined };
            },
            .no_header => {
                if (header_defined or footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.NoHeaderInMarginal;
                }
                slide.exclude_header = true;
            },
            .no_footer => {
                if (header_defined or footer_defined) {
                    std.log.err("Line {} | Parser interupt", .{ lexer.line });
                    return error.NoFooterInMarginal;
                }
                slide.exclude_footer = true;
            },
            .quad => |color_quad| {
                const location: SectionLocation = if (footer_defined)
                    .{ .marginal = &state.slide_show.footer }
                else if (header_defined)
                    .{ .marginal = &state.slide_show.header }
                else
                    .{ .slide = &slide };

                section.section_type = .{ .quad = color_quad };
                try addSection(location, &section);
            },
            .left_space => |space| {
                section.left_space = space;
            },
            .right_space => |space| {
                section.right_space = space;
            },
        }
    }

    // create the last slide
    try state.slide_show.slides.append(slide);

    if (state.slide_show.slides.items.len > 999) return error.TooManySlides;
    std.log.debug("Parsed slide show.", .{});
}

fn loadSlidesFromFile(file_path: []const u8) void {
    const file_contents = data.readEntireFile(file_path, state.allocator) catch |err| {
        std.log.err("{s} | Unable to read file '{s}'.", .{ @errorName(err), file_path });
        return;
    };
    defer file_contents.deinit();

    state.window.display_black_bars = true;

    parseSlideShow(file_contents.items) catch |e| {
        std.log.err("{s} | Unable to parse slide show file '{s}'.", .{ @errorName(e), file_path });
        return;
    };
    state.renderer.loadSlideData();

    std.log.info("Successfully loaded slide show file: '{s}'.", .{ file_path });
}

fn unloadSlideShow() void {
    state.slide_show.unloadSlides();
    state.window.display_black_bars = false;
    state.window.forceViewportAspectRatio(null);
    state.window.updateViewport(state.window.size_x, state.window.size_y);
    state.renderer.updateMatrices();
    state.renderer.clear();
    c.glfwPostEmptyEvent(); // for render refresh
    std.log.debug("Unloaded slide show.", .{});
}

pub fn reloadSlideShow() !void {
    assert(state.slide_show.fileIsTracked());
    const slide_index = state.slide_show.slide_index;

    unloadSlideShow();
    std.log.info("Reloading slide show...", .{});
    loadSlidesFromFile(state.slide_show.tracked_file.items);

    state.slide_show.slide_index = @min(state.slide_show.slides.items.len -| 1, slide_index);
}

pub fn loadSlideShow(file_path: [:0]const u8) !void {
    const full_file_path = try std.fs.realpathAlloc(state.allocator, file_path);
    defer state.allocator.free(full_file_path);

    state.slide_show.tracked_file.clearRetainingCapacity();
    try state.slide_show.tracked_file.appendSlice(full_file_path);

    unloadSlideShow();
    loadSlidesFromFile(full_file_path);

    // init file watcher
    if (state.slide_show.watched_dir_id != null) c.dmon_unwatch(state.slide_show.watched_dir_id.?);
    const dir_path = state.slide_show.loadedFileDir();
    const dir_path_c_string = try state.allocator.allocSentinel(u8, dir_path.len, 0);
    defer state.allocator.free(dir_path_c_string);
    @memcpy(dir_path_c_string, dir_path);
    state.slide_show.watched_dir_id = c.dmon_watch(dir_path_c_string, watchCallback, c.DMON_WATCHFLAGS_FOLLOW_SYMLINKS, null);

    // update window title
    var new_title = String.init(state.allocator);
    defer new_title.deinit();
    try new_title.appendSlice(win.default_title);
    assert(state.slide_show.fileIsTracked());
    try new_title.appendSlice(" | ");
    try new_title.appendSlice(state.slide_show.loadedFileName());
    try new_title.append(0); // null-termination needed

    state.window.updateTitle(new_title.items);
}

pub fn loadHomeScreenSlide() void {
    if (state.slide_show.fileIsTracked()) {
        state.slide_show.tracked_file.clearRetainingCapacity();
        state.window.updateTitle(null);
        c.dmon_unwatch(state.slide_show.watched_dir_id.?);
        state.slide_show.watched_dir_id = null;
        std.log.info("Unloaded slide show file.", .{});
    }
    unloadSlideShow();

    parseSlideShow(data.home_screen_slide) catch |e| {
        std.log.err("{s}", .{ @errorName(e) });
        return;
    };
    state.renderer.loadSlideData();
    std.log.debug("Loaded home screen slide.", .{});
}
