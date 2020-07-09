const std = @import("std");
const Bar = @import("types/bar.zig").Bar;
const Widget = @import("types/widget.zig").Widget;
const barImpl = @import("bar/bar.zig");
const textWidget = @import("widgets/text/text.zig");
const weatherWidget = @import("widgets/weather/weather.zig");
const timeWidget = @import("widgets/time/time.zig");

const DebugAllocator = @import("debug_allocator.zig");
const Info = @import("types/info.zig").Info;

pub fn main() !void {
    const debug: bool = true;
    var allocator: *std.mem.Allocator = undefined;
    var dbgAlloc: *DebugAllocator = undefined;
    if (debug) {
        dbgAlloc = &DebugAllocator.init(std.heap.page_allocator, 8192 * 8192);
        allocator = &dbgAlloc.allocator;
    } else {
        allocator = std.heap.page_allocator;
    }

    var bar = barImpl.InitBar(allocator);
    var br = Bar.init(&bar);

    const widgets = [_]*Widget{
        &Widget.init(&textWidget.New("owo", "potato")),
        &Widget.init(&textWidget.New("uwu", "tomato")),
        &Widget.init(&weatherWidget.New(allocator, &br, "London")),
        &Widget.init(&timeWidget.New(allocator, &br)),

        //&Widget.init(&weatherWidget.New(allocator, &br, "Oxford")),
        //&Widget.init(&weatherWidget.New(allocator, &br, "Newcastle")),
    };
    bar.widgets = widgets[0..];
    try br.start();
    if (debug) {
        std.debug.print("Finished cleanup, last allocation info.\n", .{});
        std.debug.print("\n{}\n", .{dbgAlloc.info});
        dbgAlloc.printRemainingStackTraces();
        dbgAlloc.deinit();
    }
}
