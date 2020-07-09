const std = @import("std");
const Info = @import("../../types/info.zig").Info;

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
            .color = "#ffaaff",
        };
    }
    pub fn info(self: *TextWidget) Info {
        return self.initial_info();
    }

    pub fn start(self: *TextWidget) anyerror!void {}
};

pub inline fn New(name: []const u8, text: []const u8) TextWidget {
    return TextWidget{
        .name = name,
        .text = text,
    };
}
