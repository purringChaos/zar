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
    network_info: []const u8,
};

inline fn freeString(allocator: *std.mem.Allocator, string: []const u8) void {
    allocator.free(string);
}

inline fn dupeString(allocator: *std.mem.Allocator, string: []const u8) ![]const u8 {
    return try allocator.dupe(u8, string);
}

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
        for (self.network_infos.items) |info| {
            freeString(self.allocator, info.network_info);
        }
        self.num_interfaces = 0;
        var proc = try std.ChildProcess.init(&[_][]const u8{ "nmcli", "-f", "common", "-c", "no", "d" }, self.allocator);
        defer { _ = proc.kill() catch {}; proc.deinit(); }
        proc.stdout_behavior = .Pipe;
        try proc.spawn();
        var i: u8 = 0;
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
                try self.network_infos.resize(i+1);
                self.network_infos.items[i]  = NetworkInfo{
                    .network_type = toNetworkType(connection_type.?),
                    .network_status = toNetworkStatus(status.?),
                    .network_info = try dupeString(self.allocator, description.?),
                };
                //try self.network_infos.append(net_info);
                self.num_interfaces += 1;
                i += 1;
            }
        }
    }

    pub fn update_bar(self: *NetworkWidget) anyerror!void {
        var buffer: [512]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        var allocator = &fba.allocator;
        for (self.network_infos.items) |info, i| {
            if (i != self.current_interface) continue;
            //std.log.debug(.network, "item! {} {}\n", .{ info, i });
            const inner_text =  try std.fmt.allocPrint(allocator, "{} {}", .{ @tagName(info.network_type), info.network_info });
            const full_text = try colour(allocator, networkStatusToColour(info.network_status), inner_text);
            defer allocator.free(full_text);
            allocator.free(inner_text);

            try self.bar.add(Info{
                .name = "network",
                .full_text = full_text,
                .markup = "pango",
            });
        }
    }

    pub fn start(self: *NetworkWidget) anyerror!void {
        self.network_infos = std.ArrayList(NetworkInfo).init(self.allocator);
        defer self.network_infos.deinit();
        while (self.bar.keep_running()) {
            try self.update_network_infos();
            try self.update_bar();
            std.time.sleep(std.time.ns_per_s);
        }
        const lock = self.update_mutex.acquire();
        defer lock.release();
        for (self.network_infos.items) |info| {
            freeString(self.allocator, info.network_info);
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
