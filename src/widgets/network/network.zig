const std = @import("std");
const Info = @import("../../types/info.zig");
const MouseEvent = @import("../../types/mouseevent.zig");
const Bar = @import("../../types/bar.zig").Bar;
const fs = std.fs;
const cwd = fs.cwd;
const colour = @import("../../formatting/colour.zig").colour;
const comptimeColour = @import("../../formatting/colour.zig").comptimeColour;
const eql = std.mem.eql;

pub const NetworkType = enum(u2) {
    WiFi = 0,
    Ethernet = 1,
    Unknown = 2,
};

fn toNetworkType(str: []const u8) NetworkType {
    if (eql(u8, str, "wifi")) return NetworkType.WiFi;
    if (eql(u8, str, "ethernet")) return NetworkType.Ethernet;
    return NetworkType.Unknown;
}

pub const NetworkStatus = enum(u3) {
    Connected = 0,
    Disconnected = 1,
    Unavailable = 2,
    Unmanaged = 3,
    Unknown = 4,
};

fn toNetworkStatus(str: []const u8) NetworkStatus {
    if (eql(u8, str, "connected")) return NetworkStatus.Connected;
    if (eql(u8, str, "disconnected")) return NetworkStatus.Disconnected;
    if (eql(u8, str, "unavailable")) return NetworkStatus.Unavailable;
    if (eql(u8, str, "unmanaged")) return NetworkStatus.Unmanaged;
    return NetworkStatus.Unknown;
}

fn networkStatusToColour(s: NetworkStatus) []const u8 {
    return switch (s) {
        .Connected => "green",
        .Disconnected => "red",
        else => "darkest",
    };
}

pub const NetworkInfo = struct {
    network_type: NetworkType = .WiFi,
    network_status: NetworkStatus = .Connected,
    network_info: [32]u8 = [32]u8{ ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
    network_info_len: usize,
};

pub const NetworkWidget = struct {
    bar: *Bar,
    allocator: *std.mem.Allocator,
    network_infos: std.ArrayList(NetworkInfo),
    num_interfaces: u8 = 0,
    current_interface: u8 = 0,
    update_mutex: std.Mutex = std.Mutex.init(),

    pub fn name(self: *NetworkWidget) []const u8 {
        return "network";
    }
    pub fn initial_info(self: *NetworkWidget) Info {
        return Info{
            .name = "network",
            .full_text = "network",
            .markup = "pango",
        };
    }
    pub fn mouse_event(self: *NetworkWidget, event: MouseEvent) void {
        {
            const lock = self.update_mutex.acquire();
            defer lock.release();
            if (self.num_interfaces == self.current_interface) {
                self.current_interface = 0;
            } else {
                self.current_interface += 1;
            }
        }
        self.update_bar() catch |err| {
            std.log.err(.network, "Error! {}\n", .{err});
        };
    }

    pub fn update_network_infos(self: *NetworkWidget) anyerror!void {
        const lock = self.update_mutex.acquire();
        defer lock.release();
        self.network_infos.shrink(0);
        self.num_interfaces = 0;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;
        var proc = try std.ChildProcess.init(&[_][]const u8{ "nmcli", "-f", "common", "-c", "no", "d" }, allocator);
        proc.stdout_behavior = .Pipe;
        try proc.spawn();
        if (proc.stdout) |stdout| {
            var line_buffer: [128]u8 = undefined;
            // Skip header.
            _ = try stdout.reader().readUntilDelimiterOrEof(&line_buffer, '\n');

            while (try stdout.reader().readUntilDelimiterOrEof(&line_buffer, '\n')) |row| {
                var it = std.mem.tokenize(row, " ");
                _ = it.next(); // Skip interface name
                const connection_type = it.next();
                const status = it.next();
                const description = it.next();
                if (connection_type) |t| if (!(eql(u8, t, "wifi") or eql(u8, t, "ethernet"))) continue;
                var net_info = NetworkInfo{
                    .network_type = toNetworkType(connection_type.?),
                    .network_status = toNetworkStatus(status.?),
                    .network_info_len = description.?.len,
                };
                std.mem.copy(u8, net_info.network_info[0..description.?.len], description.?[0..description.?.len]);

                try self.network_infos.append(net_info);
                self.num_interfaces += 1;
            }
        }
    }

    pub fn update_bar(self: *NetworkWidget) anyerror!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;
        for (self.network_infos.items) |info, i| {
            if (i != self.current_interface) continue;
            //std.log.debug(.network, "item! {} {}\n", .{ info, i });

            try self.bar.add(Info{
                .name = "network",
                .full_text = try colour(allocator, networkStatusToColour(info.network_status), try std.fmt.allocPrint(allocator, "{} {}", .{ @tagName(info.network_type), info.network_info[0..info.network_info_len] })),
                .markup = "pango",
            });
        }
    }

    pub fn start(self: *NetworkWidget) anyerror!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;
        self.network_infos = std.ArrayList(NetworkInfo).init(allocator);
        while (self.bar.keep_running()) {
            try self.update_network_infos();
            try self.update_bar();
            std.time.sleep(std.time.ns_per_s);
        }
    }
};

pub inline fn New(allocator: *std.mem.Allocator, bar: *Bar) NetworkWidget {
    return NetworkWidget{
        .allocator = allocator,
        .bar = bar,
        .network_infos = undefined,
    };
}
