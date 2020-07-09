const std = @import("std");
const net = std.net;
const io = std.io;
const hzzp = @import("hzzp");
const Info = @import("../../types/info.zig").Info;
const Bar = @import("../../types/bar.zig").Bar;
const colour = @import("../../formatting/colour.zig").colour;
const DebugAllocator = @import("../../debug_allocator.zig");

pub const WeatherWidget = struct {
    allocator: *std.mem.Allocator,
    bar: *Bar,
    weather_api_url: []const u8,
    info: ?Info,
    mutex: std.Mutex,

    pub fn name(self: *WeatherWidget) []const u8 {
        return "weather";
    }
    pub fn initial_info(self: *WeatherWidget) Info {
        return Info{
            .name = "weather",
            .full_text = "weather",
            .markup = "pango",
            .color = "#ffffff",
        };
    }
    pub fn info(self: *WeatherWidget) Info {
        const lock = self.mutex.acquire();
        defer lock.release();
        if (self.info == null) {
            return self.initial_info();
        } else {
            return self.info.?;
        }
    }

    pub fn start(self: *WeatherWidget) anyerror!void {
        defer self.mutex.deinit();
        while (self.bar.keep_running()) {
            std.time.sleep(2000 * std.time.ns_per_ms);

            std.debug.print("Starting Weather Widget.\n", .{});
            var file = try net.tcpConnectToHost(self.allocator, "api.openweathermap.org", 80);
            std.debug.print("Connected to OpenWeatherMap.\n", .{});

            var read_buffer: [512]u8 = undefined;
            var client = hzzp.BaseClient.create(&read_buffer, &file.reader(), &file.writer());

            try client.writeHead("GET", self.weather_api_url);
            try client.writeHeader("Host", "api.openweathermap.org");
            try client.writeHeader("User-Agent", "uwu/1.2");
            try client.writeHeader("Connection", "close");
            try client.writeHeader("Accept", "*/*");
            try client.writeHeadComplete();

            std.debug.print("Wrote Data, reading response.\n", .{});

            var isNextTemp: bool = false;
            var isNextMain: bool = false;
            var foundMain: bool = false;

            var temp: u16 = undefined;
            var main: []const u8 = undefined;

            while (try client.readEvent()) |event| {
                switch (event) {
                    .chunk => |chunk| {
                        var tokens = std.json.TokenStream.init(chunk.data);
                        while (try tokens.next()) |token| {
                            switch (token) {
                                .String => |string| {
                                    var str = string.slice(tokens.slice, tokens.i - 1);
                                    if (std.mem.eql(u8, str, "temp")) {
                                        isNextTemp = true;
                                        continue;
                                    }
                                    if (!foundMain and std.mem.eql(u8, str, "main")) {
                                        isNextMain = true;
                                        continue;
                                    }
                                    if (isNextMain) {
                                        main = str;
                                        isNextMain = false;
                                        foundMain = true;
                                    }
                                },
                                .Number => |num| {
                                    if (isNextTemp) {
                                        isNextTemp = false;
                                        temp = @floatToInt(u16, std.math.round(try std.fmt.parseFloat(f32, num.slice(tokens.slice, tokens.i - 1))));
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    .status, .header, .head_complete, .closed, .end, .invalid => continue,
                }
            }
            var tempColour: []const u8 = "green";
            if (temp >= 20) {
                tempColour = "red";
            } else if (temp == 19) {
                tempColour = "orange";
            } else if (temp == 18) {
                tempColour = "yellow";
            }
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            var arenacator = &arena.allocator;
            if (self.info != null) {
                self.allocator.free(self.info.?.full_text);
            }

            var i = Info{
                .name = "weather",
                .full_text = try std.fmt.allocPrint(self.allocator, "{} {}{}{} {}", .{
                    colour(arenacator, "accentlight", "weather"),
                    colour(arenacator, tempColour, try std.fmt.allocPrint(arenacator, "{}", .{temp})),
                    colour(arenacator, "accentlight", "°"),
                    colour(arenacator, "accentdark", "C"),
                    colour(arenacator, "green", main),
                }),
                .markup = "pango",
                .color = "#ffffff",
            };
            const lock = self.mutex.acquire();
            self.info = i;
            lock.release();

            arena.deinit();
        }
    }
};

pub inline fn New(allocator: *std.mem.Allocator, bar: *Bar, comptime location: []const u8) WeatherWidget {
    return WeatherWidget{
        .allocator = allocator,
        .bar = bar,
        .weather_api_url = "/data/2.5/weather?q=" ++ location ++ "&appid=dcea3595afe693d1c17846141f58ea10&units=metric",
        .info = null,
        .mutex = std.Mutex.init(),
    };
}
