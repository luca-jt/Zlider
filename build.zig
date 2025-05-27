const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "Zlider",
        .root_module = exe_mod,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("rt");
    exe.linkSystemLibrary("m");
    exe.linkSystemLibrary("dl");

    exe.addIncludePath(b.path("extern"));

    exe.defineCMacroRaw("GLFW_INCLUDE_NONE");
    exe.defineCMacroRaw("STBI_ONLY_JPEG");
    exe.defineCMacroRaw("STBI_ONLY_PNG");
    exe.defineCMacroRaw("STBI_SUPPORT_ZLIBS");
    exe.defineCMacroRaw("STB_IMAGE_IMPLEMENTATION");
    exe.defineCMacroRaw("STBI_WINDOWS_UTF8");
    exe.defineCMacroRaw("STB_IMAGE_WRITE_IMPLEMENTATION");
    exe.defineCMacroRaw("STBIW_WINDOWS_UTF8");
    exe.defineCMacroRaw("STB_TRUETYPE_IMPLEMENTATION");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
