pub usingnamespace @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("glfw3.h");
    @cInclude("glad.h");
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
    @cInclude("stb_truetype.h");
    @cInclude("pdfgen.h");
    @cInclude("time.h");
    @cInclude("dmon.h");
});
