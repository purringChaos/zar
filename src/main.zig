const std = @import("std");
const Bar = @import("types/bar.zig").Bar;
const Widget = @import("types/widget.zig").Widget;
const barImpl = @import("bar/bar.zig");
const textWidget = @import("widgets/text/text.zig");
const weatherWidget = @import("widgets/weather/weather.zig");
const DebugAllocator = @import("debug_allocator.zig");
const colour = @import("formatting/colour.zig").colour;

pub fn main() !void {
    const dbgAlloc = &DebugAllocator.init(std.heap.page_allocator, 8192 * 512);
    defer {
        std.debug.print("Finished cleanup, last allocation info.\n", .{});
        std.debug.print("\n{}\n", .{dbgAlloc.info});
        dbgAlloc.printRemainingStackTraces();
        dbgAlloc.deinit();
    }
    var allocator = &dbgAlloc.allocator;
    var bar = barImpl.InitBar(allocator);
    var br = Bar.init(&bar);

    var arena = std.heap.ArenaAllocator.init(allocator);
    var arenacator = &arena.allocator;

    const widgets = [_]*Widget{
        &Widget.init(&textWidget.New("owo", "potato")),
        &Widget.init(&weatherWidget.New(arenacator, &br, "London")),
    };
    bar.widgets = widgets[0..];
    try br.start();
    arena.deinit();
}
