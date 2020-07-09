const std = @import("std");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("zar", "src/main.zig");

    exe.addPackage(.{
        .name = "interfaces",
        .path = "deps/interfaces/interface.zig",
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
