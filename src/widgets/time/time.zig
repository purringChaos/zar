const std = @import("std");
const Info = @import("../../types/info.zig");
const Bar = @import("../../types/bar.zig").Bar;
const time = @import("time");
const colour = @import("../../formatting/colour.zig").colour;
const MouseEvent = @import("../../types/mouseevent.zig");
const comptimeColour = @import("../../formatting/colour.zig").comptimeColour;

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

    pub fn mouse_event(self: *TimeWidget, event: MouseEvent) void {}

    pub fn start(self: *TimeWidget) anyerror!void {
        // TODO: find a god damn decent time library thats better than this bullshit.
        while (self.bar.keep_running()) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            var allocator = &arena.allocator;
            var local = time.Location.getLocal(allocator);
            var now = time.now(&local);
            var date = now.date();
            var clock = now.clock();

            var hour: isize = clock.hour;
            var end: []const u8 = "";
            if (hour >= 12) {
                if (hour >= 13) {
                    hour = hour - 12;
                }
                end = "pm";
            } else {
                end = "am";
            }

            var timeStr = try std.fmt.allocPrint(allocator, "{}{}{}{}{}{}", .{
                colour(allocator, "red", try std.fmt.allocPrint(allocator, "{d:0<2}", .{@intCast(u7, hour)})),
                comptimeColour("accentlight", ":"),
                colour(allocator, "orange", try std.fmt.allocPrint(allocator, "{d:0<2}", .{@intCast(u7, clock.min)})),
                comptimeColour("accentmedium", ":"),
                colour(allocator, "yellow", try std.fmt.allocPrint(allocator, "{d:0<2}", .{@intCast(u7, clock.sec)})),
                colour(allocator, "accentdark", end),
            });

            var suffix: []const u8 = "th";
            if (@mod(date.day, 10) == 1) {
                if (@mod(date.day, 100) != 11) {
                    suffix = "st";
                }
            } else if (@mod(date.day, 10) == 2) {
                if (@mod(date.day, 100) != 12) {
                    suffix = "nd";
                }
            } else if (@mod(date.day, 10) == 3) {
                if (@mod(date.day, 100) != 13) {
                    suffix = "rd";
                }
            }

            var h = try std.fmt.allocPrint(allocator, "{} {} {}{} {} {} {} {} {} {}", .{
                colour(allocator, "green", now.weekday().string()),
                comptimeColour("purple", "the"),
                colour(allocator, "yellow", try std.fmt.allocPrint(allocator, "{}", .{date.day})),
                colour(allocator, "accentmedium", suffix),
                comptimeColour("purple", "of"),
                colour(allocator, "red", date.month.string()),
                comptimeColour("purple", "in"),
                colour(allocator, "accentlight", try std.fmt.allocPrint(allocator, "{}", .{date.year})),
                comptimeColour("purple", "at"),
                timeStr,
            });

            try self.bar.add(Info{
                .name = "time",
                .full_text = h,
                .markup = "pango",
            });

            std.time.sleep(200 * std.time.ns_per_ms);
        }
    }
};

pub inline fn New(allocator: *std.mem.Allocator, bar: *Bar) TimeWidget {
    return TimeWidget{
        .allocator = allocator,
        .bar = bar,
    };
}
