const std = @import("std");
const Bar = @import("types/bar.zig").Bar;
const Widget = @import("types/widget.zig").Widget;
const barImpl = @import("bar/bar.zig");
const terminalBar = @import("bar/bar.zig");

const textWidget = @import("widgets/text/text.zig");
const weatherWidget = @import("widgets/weather/weather.zig");
const timeWidget = @import("widgets/time/time.zig");
const batteryWidget = @import("widgets/battery/battery.zig");
const memoryWidget = @import("widgets/memory/memory.zig");
const cpuWidget = @import("widgets/cpu/cpu.zig");
const networkWidget = @import("widgets/network/network.zig");

const DebugAllocator = @import("debug_allocator.zig");
const Info = @import("types/info.zig");

const debug_allocator = @import("build_options").debug_allocator;

// Set the log level to warning
pub const log_level: std.log.Level = .warn;
// Define root.log to override the std implementation
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-critical logging from sources other than
    // .my_project and .nice_library
    const prefix_text = switch (level) {
        .emerg => "EMER",
        .alert => "ALER",
        .crit => "CRIT",
        .err => "ERROR",
        .warn => "WARN",
        .notice => "NOTI",
        .info => "INFO",
        .debug => "DBUG",
    };
    var format_text: []const u8 = "";
    const prefix = prefix_text ++ "[" ++ @tagName(scope) ++ "] ";
    const held = std.debug.getStderrMutex().acquire();
    defer held.release();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format, args) catch return;
}

pub fn main() !void {
    std.log.info("Starting Bar.", .{});
    var allocator: *std.mem.Allocator = undefined;
    var dbgAlloc: DebugAllocator = undefined;
    var arena: std.heap.ArenaAllocator = undefined;
    if (debug_allocator) {
        // Warning that DebugAllocator can get a little crashy.
        dbgAlloc = DebugAllocator.init(std.heap.page_allocator, 8192 * 8192);
        allocator = &dbgAlloc.allocator;
    } else {
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        allocator = &arena.allocator;
    }
    defer {
        if (!debug_allocator) arena.deinit();
    }

    var bar = barImpl.initBar(allocator);
    var br = Bar.init(&bar);

    const widgets = [_]*Widget{
        //&Widget.init(&networkWidget.New(allocator, &br)), // 24.01KiB
        &Widget.init(&cpuWidget.New(&br)), // 4.08KiB
        &Widget.init(&memoryWidget.New(&br)), // 4.08KiB
        &Widget.init(&weatherWidget.New(allocator, &br, @import("build_options").weather_location)), // 16.16KiB
        &Widget.init(&batteryWidget.New(allocator, &br)), // 12.11KiB
        &Widget.init(&timeWidget.New(allocator, &br)), // 32.46KiB
    };
    bar.widgets = widgets[0..];
    try br.start();
    if (debug_allocator) {
        std.debug.print("Finished cleanup, last allocation info.\n", .{});
        std.debug.print("\n{}\n", .{dbgAlloc.info});
        dbgAlloc.printRemainingStackTraces();
        dbgAlloc.deinit();
    }
}
