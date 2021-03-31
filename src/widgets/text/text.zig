const std = @import("std");
const Info = @import("../../types/info.zig");
const MouseEvent = @import("../../types/mouseevent.zig");

pub const TextWidget = struct {
    name: []const u8,
    text: []const u8,

    pub fn name(self: *TextWidget) []const u8 {
        return self.name;
    }
    pub fn initial_info(self: *TextWidget) Info {
        return Info{
            .name = self.name,
            .full_text = self.text,
            .markup = "pango",
        };
    }
    pub fn mouse_event(self: *TextWidget, event: MouseEvent) void {}

    pub fn start(self: *TextWidget) anyerror!void {}
};
pub fn New(name: []const u8, text: []const u8) callconv(.Inline) TextWidget {
    return TextWidget{
        .name = name,
        .text = text,
    };
}
