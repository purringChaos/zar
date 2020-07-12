const interface = @import("interfaces");
const Interface = interface.Interface;
const SelfType = interface.SelfType;
const Info = @import("info.zig").Info;

pub const Widget = struct {
    const IFace = Interface(struct {
        name: fn (*SelfType) []const u8,
        initial_info: fn (*SelfType) Info,
        start: fn (*SelfType) anyerror!void,
    }, interface.Storage.NonOwning);
    iface: IFace,
    pub fn init(impl_ptr: var) Widget {
        return .{ .iface = try IFace.init(.{impl_ptr}) };
    }
    pub fn name(self: *Widget) []const u8 {
        return self.iface.call("name", .{});
    }
    pub fn initial_info(self: *Widget) Info {
        return self.iface.call("initial_info", .{});
    }
    pub fn start(self: *Widget) anyerror!void {
        return self.iface.call("start", .{});
    }
};
