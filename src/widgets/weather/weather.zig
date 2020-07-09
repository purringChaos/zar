const std = @import("std");
const net = std.net;
const io = std.io;
const hzzp = @import("hzzp");
const Info = @import("../../types/info.zig").Info;
const Bar = @import("../../types/bar.zig").Bar;
const colour = @import("../../formatting/colour.zig").colour;
const DebugAllocator = @import("../../debug_allocator.zig");

const WeatherData = struct {
    temp: u16,
    main: []const u8,
};

pub const WeatherWidget = struct {
    allocator: *std.mem.Allocator,
    bar: *Bar,
    name: []const u8,
    weather_api_url: []const u8,

    pub fn name(self: *WeatherWidget) []const u8 {
        return self.name;
    }
    pub fn initial_info(self: *WeatherWidget) Info {
        return Info{
            .name = self.name,
            .full_text = "weather",
            .markup = "pango",
        };
    }
    pub fn info(self: *WeatherWidget) Info {
        return self.initial_info();
    }

    fn get_weather_info(self: *WeatherWidget, allocator: *std.mem.Allocator) !WeatherData {
        // this will allocate some memory but it will be freed by the time it is returned.
        var file = try net.tcpConnectToHost(allocator, "api.openweathermap.org", 80);

        var read_buffer: [512 * 512]u8 = undefined;
        var client = hzzp.BaseClient.create(&read_buffer, &file.reader(), &file.writer());

        try client.writeHead("GET", self.weather_api_url);
        try client.writeHeader("Host", "api.openweathermap.org");
        try client.writeHeader("User-Agent", "uwu/1.2");
        try client.writeHeader("Connection", "close");
        try client.writeHeader("Accept", "*/*");
        try client.writeHeadComplete();

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
        return WeatherData{ .temp = temp, .main = main };
    }

    fn update_info(self: *WeatherWidget) anyerror!void {
        std.debug.print("uwu!!\n", .{});

        var inf: WeatherData = undefined;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var arenacator = &arena.allocator;
        if (self.get_weather_info(arenacator)) |i| {
            inf = i;
        } else |err| switch (err) {
            error.TemporaryNameServerFailure => {
                try self.bar.add(Info{
                    .name = self.name,
                    .full_text = "weather DNS Error with a chance of WiFi",
                    .markup = "pango",
                });
            },
            error.InvalidIPAddressFormat => {
                try self.bar.add(Info{
                    .name = self.name,
                    .full_text = "invalid IP",
                    .markup = "pango",
                });
            },
            else => |e| {
                std.debug.print("\n\n\n\n\nError!: {}\n\n\n\n\n", .{@errorName(e)});
            },
        }

        var temp = inf.temp;
        var main = inf.main;

        var tempColour: []const u8 = "green";
        if (temp >= 20) {
            tempColour = "red";
        } else if (temp == 19) {
            tempColour = "orange";
        } else if (temp == 18) {
            tempColour = "yellow";
        }
        var i = Info{
            .name = self.name,
            .full_text = try std.fmt.allocPrint(arenacator, "{} {}{}{} {}", .{
                colour(arenacator, "accentlight", "weather"),
                colour(arenacator, tempColour, try std.fmt.allocPrint(arenacator, "{}", .{temp})),
                colour(arenacator, "accentlight", "°"),
                colour(arenacator, "accentdark", "C"),
                colour(arenacator, "green", main),
            }),
            .markup = "pango",
        };
        try self.bar.add(i);
    }

    pub fn start(self: *WeatherWidget) anyerror!void {
        while (self.bar.keep_running()) {
            try self.update_info();
        }
    }
};

pub inline fn New(allocator: *std.mem.Allocator, bar: *Bar, comptime location: []const u8) WeatherWidget {
    return WeatherWidget{
        .allocator = allocator,
        .bar = bar,
        .name = "weather " ++ location,
        .weather_api_url = "/data/2.5/weather?q=" ++ location ++ "&appid=dcea3595afe693d1c17846141f58ea10&units=metric",
    };
}
