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
const marqueeTextWidget = @import("widgets/marqueetext/marqueetext.zig");

const DebugAllocator = @import("debug_allocator.zig");
const Info = @import("types/info.zig");

const debug_allocator = @import("build_options").debug_allocator;

pub fn main() !void {
    var allocator: *std.mem.Allocator = undefined;
    var dbgAlloc: *DebugAllocator = undefined;
    if (debug_allocator) {
        // Warning that DebugAllocator can get a little crashy.
        dbgAlloc = &DebugAllocator.init(std.heap.page_allocator, 8192 * 8192);
        allocator = &dbgAlloc.allocator;
    } else {
        allocator = std.heap.page_allocator;
    }
    var bar = barImpl.initBar(allocator);
    var br = Bar.init(&bar);

    const widgets = [_]*Widget{
        //&Widget.init(&textWidget.New("owo", "potato")), // 4KiB
        //&Widget.init(&textWidget.New("uwu", "tomato")), // 4KiB
        //&Widget.init(&cpuWidget.New(&br)), // 4.08KiB
        &Widget.init(&memoryWidget.New(&br)), // 4.08KiB
        //&Widget.init(&weatherWidget.New(allocator, &br, @import("build_options").weather_location)), // 16.16KiB
        //&Widget.init(&batteryWidget.New(allocator, &br)), // 12.11KiB
        //&Widget.init(&timeWidget.New(allocator, &br)), // 32.46KiB
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
