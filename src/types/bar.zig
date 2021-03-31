const interface = @import("interfaces");
const Interface = interface.Interface;
const SelfType = interface.SelfType;
const Info = @import("info.zig");

pub const Bar = struct {
    const IFace = Interface(struct {
        start: fn (*SelfType) anyerror!void,
        keep_running: fn (*SelfType) bool,
        add: fn (*SelfType, Info) anyerror!void,
    }, interface.Storage.NonOwning);
    iface: IFace,
    pub fn init(impl_ptr: anytype) Bar {
        return .{ .iface = try IFace.init(impl_ptr) };
    }
    pub fn keep_running(self: *Bar) bool {
        return self.iface.call("keep_running", .{});
    }
    pub fn start(self: *Bar) anyerror!void {
        return try self.iface.call("start", .{});
    }
    pub fn add(self: *Bar, info: Info) anyerror!void {
        return try self.iface.call("add", .{info});
    }
};
