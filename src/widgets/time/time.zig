const std = @import("std");
const Info = @import("../../types/info.zig").Info;
const Bar = @import("../../types/bar.zig").Bar;
const time = @import("time");

pub const TimeWidget = struct {
    bar: *Bar,
    allocator: *std.mem.Allocator,

    pub fn name(self: *TimeWidget) []const u8 {
        return "time";
    }
    pub fn initial_info(self: *TimeWidget) Info {
        return Info{
            .name = "time",
            .full_text = "TheTime™",
            .markup = "pango",
        };
    }
    pub fn info(self: *TimeWidget) Info {
        return self.initial_info();
    }

    pub fn start(self: *TimeWidget) anyerror!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;
        var local = time.Location.getLocal(allocator);
        var now = time.now(&local);
        std.debug.print("OwO: {}\n", .{now.date()});
    }
};

pub inline fn New(allocator: *std.mem.Allocator, bar: *Bar) TimeWidget {
    return TimeWidget{
        .allocator = allocator,
        .bar = bar,
    };
}
