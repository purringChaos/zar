const std = @import("std");
const Widget = @import("../types/widget.zig").Widget;
const Info = @import("../types/info.zig");
const MouseEvent = @import("../types/mouseevent.zig");
const os = std.os;
const terminal_version = @import("build_options").terminal_version;
const debug_allocator = @import("build_options").debug_allocator;
const disable_terminal_mouse = @import("build_options").disable_terminal_mouse;
const json = @import("json.zig");

fn readFromSignalFd(signal_fd: std.os.fd_t) !void {
    var buf: [@sizeOf(os.linux.signalfd_siginfo)]u8 align(8) = undefined;
    _ = try os.read(signal_fd, &buf);
    return error.Shutdown;
}

fn sigemptyset(set: *std.os.sigset_t) void {
    for (set) |*val| {
        val.* = 0;
    }
}

const log = std.log.scoped(.bar);

pub const Bar = struct {
    allocator: *std.mem.Allocator,
    widgets: []const *Widget,
    running: bool,
    infos: std.ArrayList(Info),
    items_mutex: std.Thread.Mutex,
    out_file: std.fs.File,
    pub fn start(self: *Bar) !void {
        self.running = true;
        // i3bar/swaybar requires starting with this to get click events.
        if (!terminal_version) try self.out_file.writer().writeAll("{\"version\": 1,\"click_events\": true}\n[\n");
        for (self.widgets) |w| {
            try self.infos.append(try self.dupe_info(w.initial_info()));
        }
        try self.print_infos(true);
        var mask: std.os.sigset_t = undefined;

        sigemptyset(&mask);
        os.linux.sigaddset(&mask, std.os.SIGTERM);
        os.linux.sigaddset(&mask, std.os.SIGINT);
        _ = os.linux.sigprocmask(std.os.SIG_BLOCK, &mask, null);
        const signal_fd = try os.signalfd(-1, &mask, 0);
        defer os.close(signal_fd);
        log.debug("Spawning threads.\n", .{});
        for (self.widgets) |w| {
            log.debug("Spawning thread=\"{}\"\n", .{w.name()});
            var thread = try std.Thread.spawn(Widget.start, w);
        }
        _ = try std.Thread.spawn(Bar.process, self);
        log.info("Waiting for kill signal.\n", .{});

        while (true) {
            readFromSignalFd(signal_fd) catch |err| {
                if (err == error.Shutdown) break else log.err("failed to read from signal fd: {}\n", .{err});
            };
        }
        log.info("Shutting Down.\n", .{});

        self.running = false;
        const lock = self.items_mutex.acquire();
        defer lock.release();
        // Wait for most widgets to stop.
        std.time.sleep(1000 * std.time.ns_per_ms);

        for (self.infos.items) |info| {
            try self.free_info(info);
        }
        self.infos.deinit();
        log.info("Shut Down.\n", .{});
        if (terminal_version and !disable_terminal_mouse) {
            try self.out_file.writer().writeAll("\u{001b}[?1000;1006;1015l");
        }
    }
    fn print_i3bar_infos(self: *Bar) callconv(.Inline) !void {
        // Serialize all bar items and put on stdout.
        try self.out_file.writer().writeAll("[");
        for (self.infos.items) |info, i| {
            try json.stringify(info, .{}, self.out_file.writer());

            if (i < self.infos.items.len - 1) {
                try self.out_file.writer().writeAll(",");
            }
        }
        try self.out_file.writer().writeAll("],\n");
    }
    fn print_terminal_infos(self: *Bar) callconv(.Inline) !void {
        // For terminal we just need to directly print.
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

    fn dispatch_click_event(self: *Bar, name: []const u8, event: MouseEvent) !void {
        std.log.debug("Dispatch! {} {}\n", .{ name, event });

        for (self.widgets) |w| {
            if (std.mem.eql(u8, w.name(), name)) {
                try w.mouse_event(event);
            }
        }
    }
    fn terminal_input_process(self: *Bar) callconv(.Inline) !void {
        // TODO: make work on other OSes other than xterm compatable terminals.

        // Write to stdout that we want to recieve all terminal click events.
        try self.out_file.writer().writeAll("\u{001b}[?1000;1006;1015h");

        var termios = try os.tcgetattr(0);
        // Set terminal to raw mode so that all input goes directly into stdin.
        termios.iflag &= ~@as(
            os.tcflag_t,
            os.IGNBRK | os.BRKINT | os.PARMRK | os.ISTRIP |
                os.INLCR | os.IGNCR | os.ICRNL | os.IXON,
        );
        // Disable echo so that you don't see mouse events in terminal.
        termios.lflag |= ~@as(os.tcflag_t, (os.ECHO | os.ICANON));
        termios.lflag &= os.ISIG;
        // Set terminal attributes.
        // TODO: reset on bar end.
        try os.tcsetattr(0, .FLUSH, termios);

        while (self.running) {
            var line_buffer: [128]u8 = undefined;
            // 0x1b is the ESC key which is used for sending and recieving events to xterm terminals.
            const line_opt = try std.io.getStdIn().reader().readUntilDelimiterOrEof(&line_buffer, 0x1b);
            if (line_opt) |l| {
                // I honestly have no idea what this does but I assume that it checks
                // that this is the right event?
                if (l.len < 2) continue;
                var it = std.mem.tokenize(l, ";");
                // First number is just the mouse event, skip processing it for now.
                // TODO: map mouse click and scroll events to the right enum value.
                _ = it.next();
                var x = it.next();
                var y = it.next();
                if (x == null) {
                    continue;
                }
                if (y == null) {
                    continue;
                }
                const click_x_position = try std.fmt.parseInt(u16, x.?, 10);
                // This makes it so it only works on the end of a click not the start
                // preventing a single click pressing the button twice.
                if (y.?[y.?.len - 1] == 'm') continue;

                var current_info_line_length: u16 = 0;
                for (self.infos.items) |infoItem, index| {
                    // Because the terminal output contains colour codes, we need to strip them.
                    // To do this we only count the number of characters that are actually printed.
                    var isEscape: bool = false;
                    const previous_length = current_info_line_length;
                    for (infoItem.full_text) |char| {
                        // Skip all of the escape codes.
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
                        // If we get here, it is the start of some amount of actual printed characters.
                        current_info_line_length = current_info_line_length + 1;
                    }
                    // Get the first widget that the click is in.
                    if (click_x_position <= current_info_line_length) {
                        self.dispatch_click_event(infoItem.name, .{ .button = .LeftClick, .x = click_x_position, .y = 0, .scale = 1, .height = 1, .relative_x = click_x_position - previous_length }) catch {};
                        break;
                    }
                    // Compensate for the | seporator on the terminal.
                    current_info_line_length = current_info_line_length + 1;
                }
            }
        }
    }
    fn i3bar_input_process(self: *Bar) callconv(.Inline) !void {
        var line_buffer: [512]u8 = undefined;
        while (self.running) {
            const line_opt = try std.io.getStdIn().reader().readUntilDelimiterOrEof(&line_buffer, '\n');
            if (line_opt) |l| {
                var line = l;
                if (std.mem.eql(u8, line, "[")) continue;
                // Prevention from crashing when running via `zig build run` when pressing enter key.
                if (line.len == 0) continue;
                // Why do you even do this i3bar?
                // Why cant you just send one single {} without a comma at start.
                // This is stupid and I don't get it, maybe if you were streaming the data
                // instead of looping and getting it, maybe then it would make more sense?
                // Anyway this just strips off the prefix of ',' so I can parse the json.
                if (line[0] == ',') line = line[1..line.len];
                const parseOptions = std.json.ParseOptions{ .allocator = self.allocator };
                @setEvalBranchQuota(9999999);
                const data = try std.json.parse(MouseEvent, &std.json.TokenStream.init(line), parseOptions);
                defer std.json.parseFree(MouseEvent, data, parseOptions);

                self.dispatch_click_event(data.name, data) catch {};
                // If mouse_event needs to store the event for after the call is finished,
                // it should do it by itself, this just keeps the lifetime of the event to bare minimum.
                // Free the memory allocated by the MouseEvent struct.
            }
        }
    }

    fn process(self: *Bar) !void {
        // Right now this is what we do for the debug allocator for testing memory usage.
        // If it the best code? Heck no but until we can gracefully ^C the program
        // this is the best we can do.
        // TODO: log errors.
        while (self.running) {
            if (terminal_version) {
                if (!disable_terminal_mouse) {
                    self.terminal_input_process() catch |err| {
                        log.err("failed to process terminal input: {}\n", .{err});
                    };
                }
            } else {
                self.i3bar_input_process() catch |err| {
                    log.err("failed to process i3bar input: {}\n", .{err});
                };
            }
        }
    }
    pub fn keep_running(self: *Bar) bool {
        // TODO: maybe rename this function to something more descriptive?
        return self.running;
    }

    /// This frees the name and text fields of a Info struct.
    fn free_info(self: *Bar, info: Info) !void {
        const name_size = info.name.len * @sizeOf(u8);
        const text_size = info.full_text.len * @sizeOf(u8);
        const total_size = name_size + text_size;
        //log.debug("Freeing info for \"{}\", name_size={} text_size={} total={}\n", .{ info.name, name_size, text_size, total_size });
        self.allocator.free(info.name);
        self.allocator.free(info.full_text);
    }

    /// In order to store the info and have Widgets not need to care about
    /// memory lifetime, we duplicate the info fields.
    fn dupe_info(self: *Bar, info: Info) !Info {
        // TODO: name should be comptime known, rework.
        const name_size = info.name.len * @sizeOf(u8);
        const text_size = info.full_text.len * @sizeOf(u8);
        const total_size = name_size + text_size;
        //log.debug("Duping info for \"{}\", name_size={} text_size={} total={}\n", .{ info.name, name_size, text_size, total_size });
        const new_name = try self.allocator.alloc(u8, info.name.len);
        std.mem.copy(u8, new_name, info.name);
        const new_text = try self.allocator.alloc(u8, info.full_text.len);
        std.mem.copy(u8, new_text, info.full_text);
        return Info{
            .name = new_name,
            .full_text = new_text,
            .markup = "pango", // setting markup to pango all the time seems OK for perf, no reason not to.
        };
    }
    /// Add a Info to the bar.
    pub fn add(self: *Bar, info: Info) !void {
        const lock = self.items_mutex.acquire();
        defer lock.release();
        if (!self.running) return;
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

pub fn initBar(allocator: *std.mem.Allocator) Bar {
    return Bar{
        .allocator = allocator,
        .widgets = undefined,
        .running = false,
        .infos = std.ArrayList(Info).init(allocator),
        .items_mutex = std.Thread.Mutex{},
        .out_file = std.io.getStdOut(),
    };
}
