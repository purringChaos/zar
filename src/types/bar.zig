const interface = @import("interfaces");
const Interface = interface.Interface;
const SelfType = interface.SelfType;
const Info = @import("info.zig").Info;

pub const Bar = struct {
    const IFace = Interface(struct {
        add: fn (*SelfType, *Info) anyerror!void,
        start: fn (*SelfType) anyerror!void,
    }, interface.Storage.NonOwning);
    iface: IFace,
    pub fn init(impl_ptr: var) Bar {
        return .{ .iface = try IFace.init(.{impl_ptr}) };
    }
    pub fn add(self: *Bar, i: *Info) anyerror!void {
        return try self.iface.call("add", .{i});
    }
    pub fn start(self: *Bar) anyerror!void {
        return try self.iface.call("start", .{});
    }
};
