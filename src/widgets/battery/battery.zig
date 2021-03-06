const std = @import("std");
const Info = @import("../../types/info.zig");
const Bar = @import("../../types/bar.zig").Bar;
const fs = std.fs;
const cwd = fs.cwd;
const colour = @import("../../formatting/colour.zig").colour;
const MouseEvent = @import("../../types/mouseevent.zig");
const comptimeColour = @import("../../formatting/colour.zig").comptimeColour;

pub const PowerPaths = struct {
    status_path: []const u8 = "",
    power_now_path: []const u8 = "",
    capacity_path: []const u8 = "",
    current_now_path: []const u8 = "",
    voltage_now_path: []const u8 = "",
};

pub fn readFileToUnsignedInt64(path: []const u8) u64 {
    // Calculate the max length of a u64 encoded as a string at comptime
    // adding 1 for newline and 1 for good luck.
    var buffer: [std.math.log10(std.math.maxInt(u64)) + 2]u8 = undefined;
    var file = fs.cwd().openFile(path, .{}) catch return 0;
    defer file.close();
    const siz = file.read(&buffer) catch return 0;
    return std.fmt.parseInt(u64, buffer[0 .. siz - 1], 10) catch return 0;
}

pub fn readFile(path: []const u8) ![]const u8 {
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

    pub fn mouse_event(self: *BatteryWidget, event: MouseEvent) void {}

    // Find all the paths for power info.
    pub fn get_power_paths(self: *BatteryWidget, provided_allocator: *std.mem.Allocator) anyerror!PowerPaths {
        var arena = std.heap.ArenaAllocator.init(provided_allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;

        var pp = PowerPaths{};

        var dir = try fs.cwd().openDir("/sys/class/power_supply", .{ .iterate = true });
        var iterate = dir.iterate();
        defer dir.close();
        while (try iterate.next()) |ent| {
            var ps_dir = try std.fmt.allocPrint(provided_allocator, "/sys/class/power_supply/{s}", .{ent.name});
            var supply_dir = try fs.cwd().openDir(ps_dir, .{ .iterate = true });
            var supply_iterate = supply_dir.iterate();
            defer supply_dir.close();
            while (try supply_iterate.next()) |entry| {
                if (std.mem.eql(u8, entry.name, "status")) {
                    pp.status_path = try std.fmt.allocPrint(provided_allocator, "{s}/{s}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "power_now")) {
                    pp.power_now_path = try std.fmt.allocPrint(provided_allocator, "{s}/{s}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "capacity")) {
                    pp.capacity_path = try std.fmt.allocPrint(provided_allocator, "{s}/{s}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "current_now")) {
                    pp.current_now_path = try std.fmt.allocPrint(provided_allocator, "{s}/{s}", .{ ps_dir, entry.name });
                    continue;
                }
                if (std.mem.eql(u8, entry.name, "voltage_now")) {
                    pp.voltage_now_path = try std.fmt.allocPrint(provided_allocator, "{s}/{s}", .{ ps_dir, entry.name });
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
        while (self.bar.keep_running()) {
            var can_get_watts: bool = false;

            var watts: f64 = 0;
            var descriptor: []const u8 = "";
            var sign: []const u8 = "?";
            var power_colour: []const u8 = "#ffffff";

            const capacity = @intToFloat(f64, readFileToUnsignedInt64(pp.capacity_path));
            const status = try readFile(pp.status_path);

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
                descriptor = comptimeColour("green", "(C)");
                sign = "+";
            } else if (std.mem.eql(u8, status, "Discharging")) {
                descriptor = comptimeColour("red", "(D)");
                sign = "-";
            } else if (std.mem.eql(u8, status, "Unknown")) {
                descriptor = comptimeColour("yellow", "(U)");
                sign = "?";
            }

            if (pp.power_now_path.len != 0) {
                watts = @intToFloat(f64, readFileToUnsignedInt64(pp.power_now_path)) / 1000000;
                can_get_watts = true;
            } else if (pp.current_now_path.len != 0 and pp.voltage_now_path.len != 0) {
                const current_now = @intToFloat(f64, readFileToUnsignedInt64(pp.current_now_path)) / 1000000;
                const voltage_now = @intToFloat(f64, readFileToUnsignedInt64(pp.voltage_now_path)) / 1000000;
                if (current_now == 0 or voltage_now == 0) {
                    can_get_watts = false;
                } else {
                    watts = (current_now * voltage_now);
                    can_get_watts = true;
                }
            }

            var watts_info: []const u8 = "";

            if (can_get_watts) {
                const watts_str = try std.fmt.allocPrint(self.allocator, " {s}{d:.2}W", .{ sign, watts });
                watts_info = try colour(self.allocator, "purple", watts_str);
                self.allocator.free(watts_str);
            }
            defer {
                if (can_get_watts) {
                    self.allocator.free(watts_info);
                }
            }

            const capInfo = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{capacity});
            const colourCapInfo = try colour(self.allocator, power_colour, capInfo);
            self.allocator.free(capInfo);
            defer self.allocator.free(colourCapInfo);

            var bat_info = try std.fmt.allocPrint(self.allocator, "{s} {s} {s}{s}{s}", .{
                comptimeColour("accentlight", "bat"),
                descriptor,
                colourCapInfo,
                comptimeColour("accentdark", "%"),
                watts_info,
            });
            defer self.allocator.free(bat_info);

            try self.bar.add(Info{
                .name = "battery",
                .full_text = bat_info,
                .markup = "pango",
            });
            std.time.sleep(std.time.ns_per_s);
        }
    }
};
pub fn New(allocator: *std.mem.Allocator, bar: *Bar) callconv(.Inline) BatteryWidget {
    return BatteryWidget{
        .allocator = allocator,
        .bar = bar,
    };
}
