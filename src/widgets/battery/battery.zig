const std = @import("std");
const Info = @import("../../types/info.zig");
const Bar = @import("../../types/bar.zig").Bar;
const fs = std.fs;
const cwd = fs.cwd;
const colour = @import("../../formatting/colour.zig").colour;

pub const PowerPaths = struct {
    status_path: []const u8 = "",
    power_now_path: []const u8 = "",
    capacity_path: []const u8 = "",
    current_now_path: []const u8 = "",
    voltage_now_path: []const u8 = "",
};

pub fn read_file_to_unsigned_int64(path: []const u8) u64 {
    var buffer: [std.math.log10(std.math.maxInt(u64)) + 2]u8 = undefined;
    var file = fs.cwd().openFile(path, .{}) catch return 0;
    defer file.close();
    const siz = file.read(&buffer) catch return 0;
    return std.fmt.parseInt(u64, buffer[0 .. siz - 1], 10) catch return 0;
}

pub fn read_file(path: []const u8) ![]const u8 {
    var buffer: [128]u8 = undefined;
    var file = try fs.cwd().openFile(path, .{});
    defer file.close();
    const siz = try file.readAll(&buffer);
    return if (buffer[siz - 1] == '\n') buffer[0 .. siz - 1] else buffer[0..siz];
}

pub const BatteryWidget = struct {
    bar: *Bar,
    allocator: *std.mem.Allocator,

    pub fn name(self: *BatteryWidget) []const u8 {
        return "battery";
    }
    pub fn initial_info(self: *BatteryWidget) Info {
        return Info{
            .name = "battery",
            .full_text = "bat",
            .markup = "pango",
        };
    }
    pub fn get_power_paths(self: *BatteryWidget, provided_allocator: *std.mem.Allocator) anyerror!PowerPaths {
        var arena = std.heap.ArenaAllocator.init(provided_allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;

        var pp = PowerPaths{};

        var dir = try fs.cwd().openDir("/sys/class/power_supply", .{ .iterate = true });
        var iterate = dir.iterate();
        defer dir.close();
        while (try iterate.next()) |ent| {
            var ps_dir = try std.fmt.allocPrint(provided_allocator, "/sys/class/power_supply/{}", .{ent.name});
            var supply_dir = try fs.cwd().openDir(ps_dir, .{ .iterate = true });
            var supply_iterate = supply_dir.iterate();
            defer supply_dir.close();
            while (try supply_iterate.next()) |entry| {
                if (std.mem.eql(u8, entry.name, "status")) {
                    pp.status_path = try std.fmt.allocPrint(provided_allocator, "{}/{}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "power_now")) {
                    pp.power_now_path = try std.fmt.allocPrint(provided_allocator, "{}/{}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "capacity")) {
                    pp.capacity_path = try std.fmt.allocPrint(provided_allocator, "{}/{}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "current_now")) {
                    pp.current_now_path = try std.fmt.allocPrint(provided_allocator, "{}/{}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "voltage_now")) {
                    pp.voltage_now_path = try std.fmt.allocPrint(provided_allocator, "{}/{}", .{ ps_dir, entry.name });
                    continue;
                }
            }
        }

        return pp;
    }

    pub fn start(self: *BatteryWidget) anyerror!void {
        var buffer: [1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        var ppallocator = &fba.allocator;
        const pp = try self.get_power_paths(ppallocator);
        std.debug.print("{}\n", .{pp});

        while (self.bar.keep_running()) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            var allocator = &arena.allocator;

            var can_get_watts: bool = false;

            var watts: f64 = 0;
            var descriptor: []const u8 = "";
            var sign: []const u8 = "?";
            var power_colour: []const u8 = "#ffffff";

            const capacity = @intToFloat(f64, read_file_to_unsigned_int64(pp.capacity_path));
            const status = try read_file(pp.status_path);

            if (capacity > 80) {
                power_colour = "green";
            } else if (capacity > 70) {
                power_colour = "yellow";
            } else if (capacity > 30) {
                power_colour = "orange";
            } else {
                power_colour = "red";
            }

            if (std.mem.eql(u8, status, "Charging")) {
                descriptor = try colour(allocator, "green", "(C)");
                sign = "+";
            } else if (std.mem.eql(u8, status, "Discharging")) {
                descriptor = try colour(allocator, power_colour, "(D)");
                sign = "-";
            } else if (std.mem.eql(u8, status, "Unknown")) {
                descriptor = try colour(allocator, "yellow", "(U)");
                sign = "?";
            }

            if (pp.power_now_path.len != 0) {
                watts = @intToFloat(f64, read_file_to_unsigned_int64(pp.power_now_path)) / 1000000;
                can_get_watts = true;
            } else if (pp.current_now_path.len != 0 and pp.voltage_now_path.len != 0) {
                const current_now = @intToFloat(f64, read_file_to_unsigned_int64(pp.current_now_path)) / 1000000;
                const voltage_now = @intToFloat(f64, read_file_to_unsigned_int64(pp.voltage_now_path)) / 1000000;
                if (current_now == 0 or voltage_now == 0) {
                    can_get_watts = false;
                } else {
                    watts = (current_now * voltage_now);
                    can_get_watts = true;
                }
            }

            var watts_info: []const u8 = "";

            if (can_get_watts) {
                watts_info = try colour(allocator, "purple", try std.fmt.allocPrint(allocator, " {}{d:0<2}W", .{ sign, watts }));
            }

            var bat_info = try std.fmt.allocPrint(allocator, "{} {} {}{}{}", .{
                colour(allocator, "accentlight", "bat"),
                descriptor,
                colour(allocator, power_colour, try std.fmt.allocPrint(allocator, "{d:0<2}", .{capacity})),
                colour(allocator, "accentdark", "%"),
                watts_info,
            });

            try self.bar.add(Info{
                .name = "battery",
                .full_text = bat_info,
                .markup = "pango",
            });
            std.time.sleep(std.time.ns_per_s);
        }
    }
};

pub inline fn New(allocator: *std.mem.Allocator, bar: *Bar) BatteryWidget {
    return BatteryWidget{
        .allocator = allocator,
        .bar = bar,
    };
}
