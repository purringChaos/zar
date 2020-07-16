const std = @import("std");
const Widget = @import("../types/widget.zig").Widget;
const Info = @import("../types/info.zig");
const MouseEvent = @import("../types/mouseevent.zig");
const os = std.os;
const terminal_version = @import("build_options").terminal_version;
const debug_allocator = @import("build_options").debug_allocator;

pub const Bar = struct {
    allocator: *std.mem.Allocator,
    widgets: []const *Widget,
    running: bool,
    infos: std.ArrayList(Info),
    items_mutex: std.Mutex,
    out_file: std.fs.File,
    pub fn start(self: *Bar) !void {
        self.running = true;
        if (!terminal_version) try self.out_file.writer().writeAll("{\"version\": 1,\"click_events\": true}\n[\n");
        for (self.widgets) |w| {
            try self.infos.append(try self.dupe_info(w.initial_info()));
        }
        try self.print_infos(true);
        for (self.widgets) |w| {
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

    inline fn print_i3bar_infos(self: *Bar) !void {
        try self.out_file.writer().writeAll("[");
        for (self.infos.items) |info, i| {
            try std.json.stringify(info, .{}, self.out_file.writer());

            if (i < self.infos.items.len - 1) {
                try self.out_file.writer().writeAll(",");
            }
        }
        try self.out_file.writer().writeAll("],\n");
    }

    inline fn print_terminal_infos(self: *Bar) !void {
        for (self.infos.items) |info, i| {
            try self.out_file.writer().writeAll(info.full_text);
            if (i < self.infos.items.len - 1) {
                try self.out_file.writer().writeAll("|");
            }
        }
        try self.out_file.writer().writeAll("\n");
    }

    fn print_infos(self: *Bar, should_lock: bool) !void {
        if (should_lock) {
            const lock = self.items_mutex.acquire();
            defer lock.release();
        }
        if (terminal_version) {
            self.print_terminal_infos() catch {};
        } else {
            self.print_i3bar_infos() catch {};
        }
    }

    inline fn terminal_input_process(self: *Bar) !void {
        try self.out_file.writer().writeAll("\u{001b}[?1000;1006;1015h");

        var termios = try os.tcgetattr(0);
        termios.iflag &= ~@as(
            os.tcflag_t,
            os.IGNBRK | os.BRKINT | os.PARMRK | os.ISTRIP |
            os.INLCR | os.IGNCR | os.ICRNL | os.IXON,
        );
        termios.lflag |= ~@as(os.tcflag_t, (os.ECHO | os.ICANON));
        termios.lflag &= os.ISIG;

        try os.tcsetattr(0, .FLUSH, termios);

        while (true) {
            var line_buffer: [128]u8 = undefined;

            const line_opt = try std.io.getStdIn().inStream().readUntilDelimiterOrEof(&line_buffer, 0x1b);
            if (line_opt) |l| {
                if (l.len < 2) continue;
                var it = std.mem.tokenize(l, ";");
                _ = it.next();
                const n = try std.fmt.parseInt(u64, it.next().?, 10);
                var y = it.next().?;
                if (y[y.len - 1] == 'm') continue;

                var xe: u64 = 0;
                for (self.infos.items) |infoItem, index| {
                    var isEscape: bool = false;
                    for (infoItem.full_text) |char| {
                        if (char == 0x1b) {
                            isEscape = true;
                            continue;
                        }
                        if (isEscape and char != 'm') {
                            continue;
                        }
                        if (char == 'm' and isEscape) {
                            isEscape = false;
                            continue;
                        }
                        xe = xe + 1;
                    }
                    if (n <= xe) {
                        for (self.widgets) |w| {
                            if (std.mem.eql(u8, w.name(), infoItem.name)) {
                                w.mouse_event(.{ .button = .LeftClick }) catch {};
                            }
                        }
                        //std.debug.print("Info Item Clicky{}\n", .{infoItem.name});
                        break;
                    }
                    xe = xe + 1;
                }
            }
        }
    }

    inline fn i3bar_input_process(self: *Bar) !void {
        var line_buffer: [512]u8 = undefined;
        while (self.running) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            var allocator = &arena.allocator;
            const line_opt = try std.io.getStdIn().inStream().readUntilDelimiterOrEof(&line_buffer, '\n');
            if (line_opt) |l| {
                var line = l;
                if (std.mem.eql(u8, line, "[")) continue;
                if (line.len == 0) continue;
                if (line[0] == ',') line = line[1..line.len];
                const parseOptions = std.json.ParseOptions{ .allocator = allocator };
                const data = try std.json.parse(MouseEvent, &std.json.TokenStream.init(line), parseOptions);
                for (self.widgets) |w| {
                    if (std.mem.eql(u8, w.name(), data.name)) {
                        w.mouse_event(data) catch {};
                    }
                }
                std.json.parseFree(MouseEvent, data, parseOptions);
            }
        }
    }

    fn process(self: *Bar) !void {
        if (debug_allocator) {
            std.time.sleep(std.time.ns_per_ms * 2000 * 5);
            if (true) return;
        }

        if (terminal_version) {
            self.terminal_input_process() catch {};
        } else {
            self.i3bar_input_process() catch {};
        }
    }
    pub fn keep_running(self: *Bar) bool {
        return self.running;
    }
    fn free_info(self: *Bar, info: Info) !void {
        self.allocator.free(info.name);
        self.allocator.free(info.full_text);
    }

    /// In order to store the info and have Widgets not need to care about
    /// memory lifetime, we duplicate the info fields.
    fn dupe_info(self: *Bar, info: Info) !Info {
        // TODO: name should be comptime known, rework.
        const new_name = try self.allocator.alloc(u8, info.name.len);
        std.mem.copy(u8, new_name, info.name);
        const new_text = try self.allocator.alloc(u8, info.full_text.len);
        std.mem.copy(u8, new_text, info.full_text);
        return Info{
            .name = new_name,
            .full_text = new_text,
            .markup = "pango",
        };
    }

    pub fn add(self: *Bar, info: Info) !void {
        const lock = self.items_mutex.acquire();
        defer lock.release();
        for (self.infos.items) |infoItem, index| {
            if (std.mem.eql(u8, infoItem.name, info.name)) {
                if (std.mem.eql(u8, infoItem.full_text, info.full_text)) {
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
        .items_mutex = std.Mutex.init(),
        .out_file = std.io.getStdOut(),
    };
}
