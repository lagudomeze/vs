const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Default to a fast build so `zig build run` is smooth out of the box;
    // pass -Doptimize=Debug when you want the debugger-friendly build.
    const optimize = b.option(
        std.builtin.Optimize,
        "optimize",
        "Prioritize performance, safety, or binary size (default: ReleaseFast)",
    ) orelse .fast;

    const zflecs_dep = b.dependency("zflecs", .{ .target = target, .optimize = optimize });
    const sdl_dep = b.dependency("sdl", .{ .target = target, .optimize = optimize });

    // Keep the one-line C shim in the build cache instead of a repo file.
    const sdl_shim = b.addWriteFiles();
    const sdl_c = b.addTranslateC(.{
        .root_source_file = sdl_shim.add("sdl_shim.c",
            \\#include <SDL3/SDL.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    sdl_c.addIncludePath(sdl_dep.path("include"));
    const sdl_mod = sdl_c.createModule();

    const assets_mod = b.createModule(.{
        .root_source_file = b.path("assets/assets.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("vx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zflecs", zflecs_dep.module("root"));
    mod.addImport("sdl", sdl_mod);
    mod.addImport("assets", assets_mod);
    mod.addAnonymousImport("data", .{
        .root_source_file = b.path("assets/data/data.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "vx",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vx", .module = mod },
                .{ .name = "zflecs", .module = zflecs_dep.module("root") },
            },
        }),
    });

    exe.root_module.linkLibrary(zflecs_dep.artifact("flecs"));
    exe.root_module.linkLibrary(sdl_dep.artifact("SDL3"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{ .root_module = mod });
    mod_tests.root_module.linkLibrary(zflecs_dep.artifact("flecs"));
    mod_tests.root_module.linkLibrary(sdl_dep.artifact("SDL3"));
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // QA2: focused run of the pure RunSim regression matrix. It also runs as
    // part of the default `test` step through src/root.zig; this step exists
    // so a full test log does not bury the QA metrics.
    const qa_mod = b.createModule(.{
        .root_source_file = b.path("src/qa2_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    qa_mod.addAnonymousImport("data", .{
        .root_source_file = b.path("assets/data/data.zig"),
        .target = target,
        .optimize = optimize,
    });
    const qa_tests = b.addTest(.{ .root_module = qa_mod });
    const run_qa_tests = b.addRunArtifact(qa_tests);
    const qa_step = b.step("test-qa", "Run the RUN QA2 regression matrix");
    qa_step.dependOn(&run_qa_tests.step);

    // QA3: game-level probes (aim state machine, save/load continuation,
    // help/mechanics). Test/tooling only; does not change game code.
    const qa3_mod = b.createModule(.{
        .root_source_file = b.path("src/qa3_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    qa3_mod.addImport("assets", assets_mod);
    qa3_mod.addAnonymousImport("data", .{
        .root_source_file = b.path("assets/data/data.zig"),
        .target = target,
        .optimize = optimize,
    });
    const qa3_tests = b.addTest(.{ .root_module = qa3_mod });
    const run_qa3_tests = b.addRunArtifact(qa3_tests);
    const qa3_step = b.step("test-qa3", "Run the RUN QA3 game-level probes");
    qa3_step.dependOn(&run_qa3_tests.step);
}
