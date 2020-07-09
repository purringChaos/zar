const std = @import("std");
const Widget = @import("../types/widget.zig").Widget;
const Info = @import("../types/info.zig").Info;

pub const Bar = struct {
    allocator: *std.mem.Allocator,
    widgets: []const *Widget,
    running: bool,
    pub fn start(self: *Bar) !void {
        self.running = true;
        for (self.widgets) |w| {
            std.debug.warn("Starting widget: {}\n", .{w.name()});
            var thread = try std.Thread.spawn(w, Widget.start);
        }
        var thread = try std.Thread.spawn(self, Bar.process);
        std.time.sleep(100000 * std.time.ns_per_ms);
        self.running = false;
        std.time.sleep(1000 * std.time.ns_per_ms);
        return;
    }
    fn process(self: *Bar) !void {
        const out_file = std.io.getStdOut();
        try out_file.writer().writeAll("{\"version\": 1,\"click_events\": true}\n[\n");
        while (self.running) {
            //std.debug.warn("I am a Square!\n", .{});
            std.time.sleep(250 * std.time.ns_per_ms);
            try out_file.writer().writeAll("[");
            for (self.widgets) |w, i| {
                try std.json.stringify(w.info(), .{}, out_file.writer());
                if (i < self.widgets.len - 1) {
                    try out_file.writer().writeAll(",");
                }
            }
            try out_file.writer().writeAll("],\n");
        }
    }
    pub fn add(self: Bar, i: *Info) void {
        std.debug.warn("Add {}!\n", .{i.name});
    }
};

pub fn InitBar(allocator: *std.mem.Allocator) Bar {
    return Bar{
        .allocator = allocator,
        .widgets = undefined,
        .running = false,
    };
}
