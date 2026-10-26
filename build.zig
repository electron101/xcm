const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "xcm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/xcm.zig"),
            .target = target,
            // .optimize = optimize,
            .optimize = .Debug,
            .link_libc = true,
            .imports = &.{
                // .{},
            },
        }),

        // for debugger
        .use_llvm = true,
        .use_lld = true,
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();

    const run_step = b.step("run", "Run XCM");

    run_step.dependOn(&run.step);
    run.step.dependOn(b.getInstallStep());
}
