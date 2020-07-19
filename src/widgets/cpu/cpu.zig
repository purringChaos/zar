const std = @import("std");
const Info = @import("../../types/info.zig");
const Bar = @import("../../types/bar.zig").Bar;
const colour = @import("../../formatting/colour.zig").colour;
const comptimeColour = @import("../../formatting/colour.zig").comptimeColour;
const MouseEvent = @import("../../types/mouseevent.zig");

fn formatCPUPercent(allocator: *std.mem.Allocator, percent: f64) ![]const u8 {
    var percentColour: []const u8 = "";
    if (percent > 80) {
        percentColour = "red";
    } else if (percent > 60) {
        percentColour = "orange";
    } else if (percent > 30) {
        percentColour = "yellow";
    } else {
        percentColour = "green";
    }
    const percentString = try std.fmt.allocPrint(allocator, "{d:0<2.2}" ++ comptimeColour("accentdark", "%"), .{percent});

    return colour(allocator, percentColour, percentString);
}

fn parseFloat(buf: []const u8) !f64 {
    return try std.fmt.parseFloat(f64, buf);
}

fn fetchCPU() ![2]f64 {
    var stat_file = try std.fs.cwd().openFile("/proc/stat", .{ .read = true, .write = false });
    defer stat_file.close();
    // data[0] = idle usage
    // data[1] = non-idle usage
    var data: [2]f64 = [2]f64{ 0.0, 0.0 };

    var line_buffer: [128]u8 = undefined;
    const line_opt = try stat_file.inStream().readUntilDelimiterOrEof(&line_buffer, '\n');
    if (line_opt) |line| {
        var it = std.mem.tokenize(line, " ");
        const stat_type = it.next().?;
        if (!std.mem.eql(u8, stat_type, "cpu")) {
            std.debug.print("First stat line wasn't CPU, Add while loop to find it.\n", .{});
            unreachable;
        }
        // Here are the fields.
        // Ones marked with (i) are idle.
        // The order for these is:
        // user nice system idle(i) iowait(i) irq softirq steal guest guest_nice
        data[1] += try parseFloat(it.next().?); // user
        data[1] += try parseFloat(it.next().?); // nice
        data[1] += try parseFloat(it.next().?); // system
        data[0] += try parseFloat(it.next().?); // idle
        data[0] += try parseFloat(it.next().?); // iowait
        data[1] += try parseFloat(it.next().?); // irq
        data[1] += try parseFloat(it.next().?); // softirq
        data[1] += try parseFloat(it.next().?); // steal
        data[1] += try parseFloat(it.next().?); // guest
        data[1] += try parseFloat(it.next().?); // guest_nice
    } else {
        unreachable;
    }

    return data;
}

pub const CPUWidget = struct {
    bar: *Bar,
    pub fn name(self: *CPUWidget) []const u8 {
        return "cpu";
    }
    pub fn initial_info(self: *CPUWidget) Info {
        return Info{
            .name = "cpu",
            .full_text = "cpu",
            .markup = "pango",
        };
    }

    pub fn mouse_event(self: *CPUWidget, event: MouseEvent) void {}

    fn update_bar(self: *CPUWidget) !void {
        // We need to calculate the difference between readings to get a more accurate reading.
        // In order to do this we need a time difference.
        const previous_stats = try fetchCPU();
        std.time.sleep(1000 * std.time.ns_per_ms);
        const next_stats = try fetchCPU();
        // Reminder that for data:
        // data[0] = idle usage
        // data[1] = non-idle usage
        const previous_total = previous_stats[0] + previous_stats[1];
        const next_total = next_stats[0] + next_stats[1];
        // Get the differences.
        const total_difference = next_total - previous_total;
        const idle_difference = next_stats[0] - previous_stats[0];
        // Work out CPU Percentage.
        const percentage = ((total_difference - idle_difference) / total_difference) * 100;

        var buffer: [256]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        var allocator = &fba.allocator;
        try self.bar.add(Info{
            .name = "cpu",
            .full_text = try std.fmt.allocPrint(allocator, "{} {}", .{
                comptimeColour("accentlight", "cpu"),
                formatCPUPercent(allocator, percentage),
            }),
            .markup = "pango",
        });
    }

    pub fn start(self: *CPUWidget) anyerror!void {
        //try self.update_bar();
        while (self.bar.keep_running()) {
            try self.update_bar();
        }
    }
};

pub inline fn New(bar: *Bar) CPUWidget {
    return CPUWidget{
        .bar = bar,
    };
}
