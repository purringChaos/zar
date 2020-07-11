const std = @import("std");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("zar", "src/main.zig");
    const disable_colour = b.option(
        bool,
        "disable_colour",
        "no colour",
    ) orelse false;
    const terminal_version = b.option(
        bool,
        "terminal_version",
        "terminal-only version",
    ) orelse false;
    exe.addBuildOption(bool, "terminal_version", terminal_version);
    exe.addBuildOption(bool, "disable_colour", disable_colour);

    exe.strip = true;
    exe.addPackage(.{
        .name = "interfaces",
        .path = "deps/interfaces/interface.zig",
    });
    exe.addPackage(.{
        .name = "time",
        .path = "deps/time/src/time.zig",
    });
    exe.addPackage(.{
        .name = "hzzp",
        .path = "deps/hzzp/src/main.zig",
    });
    exe.setBuildMode(mode);
    const run_cmd = exe.run();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
