const std = @import("std");
const Info = @import("../../types/info.zig").Info;

pub const MemoryWidget = struct {
    pub fn name(self: *MemoryWidget) []const u8 {
        return self.name;
    }
    pub fn initial_info(self: *MemoryWidget) Info {
        return Info{
            .name = "mem",
            .full_text = self.text,
            .markup = "pango",
            .color = "#ffaaff",
        };
    }
    pub fn info(self: *MemoryWidget) Info {
        return self.initial_info();
    }

    pub fn start(self: *MemoryWidget) anyerror!void {}
};

pub inline fn New(name: []const u8, Memory: []const u8) MemoryWidget {
    return MemoryWidget{
        .name = name,
        .Memory = Memory,
    };
}
