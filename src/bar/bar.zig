const std = @import("std");
const Widget = @import("../types/widget.zig").Widget;
const Info = @import("../types/info.zig").Info;

pub const Bar = struct {
    allocator: *std.mem.Allocator,
    widgets: []const *Widget,
    running: bool,
    infos: std.ArrayList(Info),
    mutex: std.Mutex,
    out_file: std.fs.File,
    pub fn start(self: *Bar) !void {
        self.running = true;
        try self.out_file.writer().writeAll("{\"version\": 1,\"click_events\": true}\n[\n");
        for (self.widgets) |w| {
            std.debug.warn("Adding Initial Info: {}\n", .{w.name()});
            try self.infos.append(try self.dupe_info(w.initial_info()));
        }
        try self.print_infos(true);
        for (self.widgets) |w| {
            std.debug.warn("Starting widget: {}\n", .{w.name()});
            var thread = try std.Thread.spawn(w, Widget.start);
        }
        var thread = try std.Thread.spawn(self, Bar.process);
        thread.wait();
        self.running = false;
        std.time.sleep(1000 * std.time.ns_per_ms);
        for (self.infos.items) |info| {
            try self.free_info(info);
        }
        self.infos.deinit();
    }

    fn print_infos(self: *Bar, should_lock: bool) !void {
        if (should_lock) {
            const lock = self.mutex.acquire();
            defer lock.release();
        }
        try self.out_file.writer().writeAll("[");
        for (self.infos.items) |info, i| {
            try std.json.stringify(info, .{}, self.out_file.writer());
            if (i < self.infos.items.len - 1) {
                try self.out_file.writer().writeAll(",");
            }
        }
        try self.out_file.writer().writeAll("],\n");
    }

    fn process(self: *Bar) !void {
        var i: i32 = 0;
        while (self.running) {
            //try self.print_infos(true);
            std.time.sleep(10000 * std.time.ns_per_ms);
            return;
        }
    }
    pub fn keep_running(self: *Bar) bool {
        return self.running;
    }
    pub fn free_info(self: *Bar, info: Info) !void {
        self.allocator.free(info.name);
        self.allocator.free(info.full_text);
    }

    pub fn dupe_info(self: *Bar, info: Info) !Info {
        const new_name = try self.allocator.alloc(u8, info.name.len);
        std.mem.copy(u8, new_name, info.name);
        const new_text = try self.allocator.alloc(u8, info.full_text.len);
        std.mem.copy(u8, new_text, info.full_text);
        var i = Info{
            .name = new_name,
            .full_text = new_text,
            .markup = "pango",
        };
        return i;
    }

    pub fn add(self: *Bar, info: Info) !void {
        const lock = self.mutex.acquire();
        defer lock.release();
        //std.debug.warn("info: {}\n", .{info.name});
        for (self.infos.items) |infoItem, index| {
            if (std.mem.eql(u8, infoItem.name, info.name)) {
                if (std.mem.eql(u8, infoItem.full_text, info.full_text)) {
                    std.debug.warn("dupe!: {}\n", .{info.name});

                    // OK so info is a dupe, we don't care about dupes so we don't do anything.
                    return;
                }
                // If we reach here then it changed.
                try self.free_info(infoItem);
                self.infos.items[index] = try self.dupe_info(info);
                try self.print_infos(false);
            }
        }
    }
};

pub fn InitBar(allocator: *std.mem.Allocator) Bar {
    return Bar{
        .allocator = allocator,
        .widgets = undefined,
        .running = false,
        .infos = std.ArrayList(Info).init(allocator),
        .mutex = std.Mutex.init(),
        .out_file = std.io.getStdOut(),
    };
}
