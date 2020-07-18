const std = @import("std");
const Info = @import("../../types/info.zig");
const Bar = @import("../../types/bar.zig").Bar;
const colour = @import("../../formatting/colour.zig").colour;
const comptimeColour = @import("../../formatting/colour.zig").comptimeColour;
const MouseEvent = @import("../../types/mouseevent.zig");
const LoopingCounter = @import("../../types/loopingcounter.zig").LoopingCounter;

const MemInfo = struct {
    memTotal: u64,
    memFree: u64,
    buffers: u64,
    cached: u64,
    swapTotal: u64,
    swapFree: u64,
    swapCached: u64,
};

fn parseKibibytes(buf: []const u8) !u64 {
    return try std.fmt.parseInt(u64, buf, 10);
}

fn kibibytesToMegabytes(i: u64) u64 {
    return (i * 1024) / 1000 / 1000;
}

fn formatMemoryPercent(allocator: *std.mem.Allocator, percent: f64) ![]const u8 {
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
    const percentString = try std.fmt.allocPrint(allocator, "{d:.2}" ++ comptimeColour("accentdark", "%"), .{percent});
    return colour(allocator, percentColour, percentString);
}

fn fetchTotalMemory() !MemInfo {
    var meminfo_file = try std.fs.cwd().openFile("/proc/meminfo", .{ .read = true, .write = false });
    defer meminfo_file.close();

    var meminfo = MemInfo{
        .memTotal = 0,
        .memFree = 0,
        .buffers = 0,
        .cached = 0,
        .swapTotal = 0,
        .swapFree = 0,
        .swapCached = 0,
    };

    while (true) {
        var line_buffer: [128]u8 = undefined;
        const line_opt = try meminfo_file.inStream().readUntilDelimiterOrEof(&line_buffer, '\n');
        if (line_opt) |line| {
            var it = std.mem.tokenize(line, " ");
            const line_header = it.next().?;
            if (std.mem.eql(u8, line_header, "MemTotal:")) {
                meminfo.memTotal = try parseKibibytes(it.next().?);
                continue;
            }
            if (std.mem.eql(u8, line_header, "MemFree:")) {
                meminfo.memFree = try parseKibibytes(it.next().?);
                continue;
            }
            if (std.mem.eql(u8, line_header, "Buffers:")) {
                meminfo.buffers = try parseKibibytes(it.next().?);
                continue;
            }
            if (std.mem.eql(u8, line_header, "Cached:")) {
                meminfo.cached = try parseKibibytes(it.next().?);
                continue;
            }
            if (std.mem.eql(u8, line_header, "SwapTotal:")) {
                meminfo.swapTotal = try parseKibibytes(it.next().?);
                continue;
            }
            if (std.mem.eql(u8, line_header, "SwapFree:")) {
                meminfo.swapFree = try parseKibibytes(it.next().?);
                continue;
            }
            if (std.mem.eql(u8, line_header, "SwapCached:")) {
                meminfo.swapCached = try parseKibibytes(it.next().?);
                continue;
            }
        } else {
            // reached eof
            break;
        }
    }

    return meminfo;
}

pub const MemoryWidget = struct {
    bar: *Bar,
    lc: *LoopingCounter(8),
    pub fn name(self: *MemoryWidget) []const u8 {
        return "mem";
    }
    pub fn initial_info(self: *MemoryWidget) Info {
        return Info{
            .name = "mem",
            .full_text = "memory",
            .markup = "pango",
        };
    }

    pub fn mouse_event(self: *MemoryWidget, event: MouseEvent) void {
        self.lc.next();
        self.update_bar() catch {};
    }

    fn update_bar(self: *MemoryWidget) !void {
        var buffer: [512]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        var allocator = &fba.allocator;
        const memInfo = try fetchTotalMemory();
        var text: []const u8 = " ";

        // And this is why I love the looping counter.
        if (self.lc.get() == 0) {
            text = try std.fmt.allocPrint(allocator, "{} {}", .{
                comptimeColour("accentlight", "mem"),
                formatMemoryPercent(allocator, (@intToFloat(f64, memInfo.memTotal - memInfo.memFree - memInfo.buffers - memInfo.cached) / @intToFloat(f64, memInfo.memTotal)) * 100),
            });
        } else if (self.lc.get() == 1) {
            text = try std.fmt.allocPrint(allocator, "{} {}", .{
                comptimeColour("accentlight", "swap"),
                formatMemoryPercent(allocator, (@intToFloat(f64, memInfo.swapTotal - memInfo.swapFree) / @intToFloat(f64, memInfo.swapTotal)) * 100),
            });
        } else if (self.lc.get() == 2) {
            text = try std.fmt.allocPrint(allocator, "{} {d:0<2} MB", .{
                comptimeColour("accentlight", "mem free"),
                kibibytesToMegabytes(memInfo.memFree),
            });
        } else if (self.lc.get() == 3) {
            text = try std.fmt.allocPrint(allocator, "{} {d:0<2} MB", .{
                comptimeColour("accentlight", "swap free"),
                kibibytesToMegabytes(memInfo.swapFree),
            });
        } else if (self.lc.get() == 4) {
            text = try std.fmt.allocPrint(allocator, "{} {d:0<2} MB", .{
                comptimeColour("accentlight", "mem used"),
                kibibytesToMegabytes(memInfo.memTotal - memInfo.memFree - memInfo.buffers - memInfo.cached),
            });
        } else if (self.lc.get() == 5) {
            text = try std.fmt.allocPrint(allocator, "{} {d:0<2} MB", .{
                comptimeColour("accentlight", "swap used"),
                kibibytesToMegabytes(memInfo.swapTotal - memInfo.swapFree),
            });
        } else if (self.lc.get() == 6) {
            text = try std.fmt.allocPrint(allocator, "{} {d:0<2} MB", .{
                comptimeColour("accentlight", "mem cache"),
                kibibytesToMegabytes(memInfo.cached),
            });
        } else if (self.lc.get() == 7) {
            text = try std.fmt.allocPrint(allocator, "{} {d:0<2} MB", .{
                comptimeColour("accentlight", "swap cache"),
                kibibytesToMegabytes(memInfo.swapCached),
            });
        } else if (self.lc.get() == 8) {
            text = try std.fmt.allocPrint(allocator, "{} {d:0<2} MB", .{
                comptimeColour("accentlight", "mem buf"),
                kibibytesToMegabytes(memInfo.buffers),
            });
        }

        try self.bar.add(Info{
            .name = "mem",
            .full_text = text,
            .markup = "pango",
        });
    }

    pub fn start(self: *MemoryWidget) anyerror!void {
        while (self.bar.keep_running()) {
            self.update_bar() catch {};
            std.time.sleep(500 * std.time.ns_per_ms);
        }
    }
};

pub inline fn New(bar: *Bar) MemoryWidget {
    return MemoryWidget{
        .bar = bar,
        .lc = &LoopingCounter(8).init(),
    };
}
