const std = @import("std");
const Info = @import("../../types/info.zig");
const MouseEvent = @import("../../types/mouseevent.zig");
const Bar = @import("../../types/bar.zig").Bar;

pub const MarqueeTextWidget = struct {
    bar: *Bar,
    texts: [][]const u8,

    pub fn name(self: *MarqueeTextWidget) []const u8 {
        return "mqtemp";
    }
    pub fn initial_info(self: *MarqueeTextWidget) Info {
        return Info{
            .name = "mqtemp",
            .full_text = "mqtemp",
            .markup = "pango",
        };
    }
    pub fn mouse_event(self: *MarqueeTextWidget, event: MouseEvent) void {}

    pub fn start(self: *MarqueeTextWidget) anyerror!void {
        while (self.bar.keep_running()) {
            for (self.texts) |y| {
                try self.bar.add(Info{
                    .name = "mqtemp",
                    .full_text = y,
                    .markup = "pango",
                });
                std.time.sleep(std.time.ns_per_ms * 250);
            }
        }
    }
};

pub inline fn New(bar: *Bar, comptime text: []const u8, comptime width: comptime_int) MarqueeTextWidget {
    const marqueedtexts = comptime blk: {
        @setEvalBranchQuota(100000000);
        comptime var new_text: []const u8 = text;
        while ((new_text.len % width) != 1) {
            comptime new_text = new_text ++ " ";
        }
        new_text = new_text ++ new_text[0 .. width - 1];
        comptime var new_texts: [new_text.len / width][width]u8 = undefined;
        var result: [new_text.len][]const u8 = undefined;
        comptime var i: i64 = 0;
        while (true) {
            result[i] = new_text[i .. i + width];
            if (i + width == new_text.len) {
                break;
            } else {
                i = i + 1;
            }
        }
        //for (new_texts) |y, i| result[i] = y[0..];

        break :blk result[0..];
    };
    return MarqueeTextWidget{
        .bar = bar,
        .texts = marqueedtexts,
    };
}
