const std = @import("std");
const Info = @import("../../types/info.zig");
const Bar = @import("../../types/bar.zig").Bar;
const colour = @import("../../formatting/colour.zig").colour;
const comptimeColour = @import("../../formatting/colour.zig").comptimeColour;
const MouseEvent = @import("../../types/mouseevent.zig");
const LoopingCounter = @import("../../types/loopingcounter.zig").LoopingCounter;


pub const CPUWidget = struct {
    bar: *Bar,
    pub fn name(self: *CPUWidget) []const u8 {
        return "cpu";
    }
    pub fn initial_info(self: *CPUWidget) Info {
        return Info{
            .name = "cpu",
            .full_text = "cpu",
            .markup = "pango",
        };
    }

    pub fn mouse_event(self: *CPUWidget, event: MouseEvent) void {}

    fn update_bar(self: *CPUWidget) !void {
    }

    pub fn start(self: *CPUWidget) anyerror!void {
        //while (self.bar.keep_running()) {
        //    self.update_bar() catch {};
        //}
    }
};

pub inline fn New(bar: *Bar) CPUWidget {
    return CPUWidget{
        .bar = bar,
    };
}
