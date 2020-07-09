const std = @import("std");
const Bar = @import("types/bar.zig").Bar;
const Widget = @import("types/widget.zig").Widget;
const barImpl = @import("bar/bar.zig");
const textWidget = @import("widgets/text/text.zig");
const weatherWidget = @import("widgets/weather/weather.zig");
const DebugAllocator = @import("debug_allocator.zig");
const colour = @import("formatting/colour.zig").colour;

const Info = @import("types/info.zig").Info;

pub const SpamWidget = struct {
    name: []const u8,
    bar: *Bar,

    pub fn name(self: *SpamWidget) []const u8 {
        return self.name;
    }
    pub fn initial_info(self: *SpamWidget) Info {
        return Info{
            .name = self.name,
            .full_text = "uwu",
            .markup = "pango",
        };
    }
    pub fn info(self: *SpamWidget) Info {
        return self.initial_info();
    }

    pub fn start(self: *SpamWidget) anyerror!void {
        var h: bool = true;
        while (self.bar.keep_running()) {
            h = !h;
            if (h) {
                try self.bar.add(Info{
                    .name = self.name,
                    .full_text = "uwu",
                    .markup = "pango",
                });
            } else {
                try self.bar.add(Info{
                    .name = self.name,
                    .full_text = "owo",
                    .markup = "pango",
                });
            }
        }
    }
};

pub inline fn NewSpam(bar: *Bar, name: []const u8) SpamWidget {
    return SpamWidget{
        .name = name,
        .bar = bar,
    };
}

pub fn main() !void {
    const dbgAlloc = &DebugAllocator.init(std.heap.page_allocator, 8192 * 512);
    defer {
        std.debug.print("Finished cleanup, last allocation info.\n", .{});
        std.debug.print("\n{}\n", .{dbgAlloc.info});
        dbgAlloc.printRemainingStackTraces();
        dbgAlloc.deinit();
    }
    var allocator = &dbgAlloc.allocator;
    //var allocator = std.heap.page_allocator;

    var bar = barImpl.InitBar(allocator);
    var br = Bar.init(&bar);

    const widgets = [_]*Widget{
        &Widget.init(&textWidget.New("owo", "potato")),
        &Widget.init(&textWidget.New("uwu", "potato")),
        &Widget.init(&NewSpam(&br, "h")),
        &Widget.init(&weatherWidget.New(allocator, &br, "London")),
        //&Widget.init(&weatherWidget.New(allocator, &br, "Newcastle")),
    };
    bar.widgets = widgets[0..];
    try br.start();
}
