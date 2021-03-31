const interface = @import("interfaces");
const Interface = interface.Interface;
const SelfType = interface.SelfType;
const Info = @import("info.zig");
const MouseEvent = @import("mouseevent.zig");

pub const Widget = struct {
    const IFace = Interface(struct {
        name: fn (*SelfType) []const u8,
        initial_info: fn (*SelfType) Info,
        mouse_event: fn (*SelfType, MouseEvent) anyerror!void,

        start: fn (*SelfType) anyerror!void,
    }, interface.Storage.NonOwning);
    iface: IFace,
    pub fn init(impl_ptr: anytype) Widget {
        return .{ .iface = try IFace.init(impl_ptr) };
    }
    pub fn name(self: *Widget) []const u8 {
        return self.iface.call("name", .{});
    }
    pub fn initial_info(self: *Widget) Info {
        return self.iface.call("initial_info", .{});
    }
    pub fn mouse_event(self: *Widget, event: MouseEvent) anyerror!void {
        return self.iface.call("mouse_event", .{event});
    }
    pub fn start(self: *Widget) anyerror!void {
        return self.iface.call("start", .{});
    }
};
