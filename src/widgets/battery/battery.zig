const std = @import("std");
const Info = @import("../../types/info.zig").Info;
const Bar = @import("../../types/bar.zig").Bar;
const fs = std.fs;
const cwd = fs.cwd;

pub fn compare_from_walker(allocator: *std.mem.Allocator, path: []const u8, start_path: []const u8, required_filename: []const u8) !bool {
    var full_path = try std.fmt.allocPrint(allocator, "{}/{}", .{ start_path, required_filename });
    defer allocator.free(full_path);
    return std.mem.eql(u8, path, full_path);
}

pub const PowerPaths = struct {
    status_path: []const u8 = "",
    power_now_path: []const u8 = "",
    capacity_path: []const u8 = "",
    current_now_path: []const u8 = "",
    voltage_now_path: []const u8 = "",
};

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
    pub fn info(self: *BatteryWidget) Info {
        return self.initial_info();
    }
    pub fn get_power_paths(self: *BatteryWidget, provided_allocator: *std.mem.Allocator) anyerror!PowerPaths {
        // remember that PowerPaths fields are allocated with self.allocator and will need to be freed seporately
        var arena = std.heap.ArenaAllocator.init(provided_allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;
        var power_supply_walker = try fs.walkPath(allocator, "/sys/class/power_supply");
        defer power_supply_walker.deinit();
        var power_supply_dirs = std.ArrayList([]const u8).init(self.allocator);
        defer power_supply_dirs.deinit();

        var pp = PowerPaths{};

        while (try power_supply_walker.next()) |entry| {
            switch (entry.kind) {
                .SymLink => {
                    try power_supply_dirs.append(entry.path);
                },
                .File,
                .BlockDevice,
                .CharacterDevice,
                .Directory,
                .NamedPipe,
                .UnixDomainSocket,
                .Whiteout,
                .Unknown,
                => continue,
            }
        }
        for (power_supply_dirs.items) |filepath| {
            var power_supply_file_walker = try fs.walkPath(allocator, filepath);
            defer power_supply_file_walker.deinit();
            while (try power_supply_file_walker.next()) |entry| {
                switch (entry.kind) {
                    .File => {
                        if (try compare_from_walker(allocator, entry.path, filepath, "status")) {
                            pp.status_path = try std.fmt.allocPrint(provided_allocator, "{}", .{entry.path});
                            continue;
                        }
                        if (try compare_from_walker(allocator, entry.path, filepath, "power_now")) {
                            pp.power_now_path = try std.fmt.allocPrint(provided_allocator, "{}", .{entry.path});
                            continue;
                        }
                        if (try compare_from_walker(allocator, entry.path, filepath, "capacity")) {
                            pp.capacity_path = try std.fmt.allocPrint(provided_allocator, "{}", .{entry.path});
                            continue;
                        }
                        if (try compare_from_walker(allocator, entry.path, filepath, "current_now")) {
                            pp.current_now_path = try std.fmt.allocPrint(provided_allocator, "{}", .{entry.path});
                            continue;
                        }
                        if (try compare_from_walker(allocator, entry.path, filepath, "voltage_now")) {
                            pp.voltage_now_path = try std.fmt.allocPrint(provided_allocator, "{}", .{entry.path});
                            continue;
                        }
                    },
                    .SymLink,
                    .BlockDevice,
                    .CharacterDevice,
                    .Directory,
                    .NamedPipe,
                    .UnixDomainSocket,
                    .Whiteout,
                    .Unknown,
                    => continue,
                }
            }
        }
        return pp;
    }

    pub fn start(self: *BatteryWidget) anyerror!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;
        const pp = try self.get_power_paths(allocator);

        std.debug.print("{} {} {} {} {}\n", .{
            pp.status_path,
            pp.power_now_path,
            pp.capacity_path,
            pp.current_now_path,
            pp.voltage_now_path,
        });
    }
};

pub inline fn New(allocator: *std.mem.Allocator, bar: *Bar) BatteryWidget {
    return BatteryWidget{
        .allocator = allocator,
        .bar = bar,
    };
}
