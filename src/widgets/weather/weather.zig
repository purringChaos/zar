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
    code: i16,
    message: []const u8,
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
        var isNextCode: bool = false;
        var isNextMessage: bool = false;

        var foundMain: bool = false;

        var temp: u16 = 0;
        var code: i16 = 0;
        var main: []const u8 = "";
        var message: []const u8 = "";

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
                                if (std.mem.eql(u8, str, "cod")) {
                                    isNextCode = true;
                                    continue;
                                }
                                if (std.mem.eql(u8, str, "message")) {
                                    isNextMessage = true;
                                    continue;
                                }
                                if (isNextMain) {
                                    main = str;
                                    isNextMain = false;
                                    foundMain = true;
                                }
                                if (isNextMessage) {
                                    message = str;
                                }
                                if (isNextCode) {
                                    // why the fuck would you make code both a string and a int are you wanting me to question my sanity???
                                    isNextCode = false;
                                    code = try std.fmt.parseInt(i16, str, 10);
                                }
                            },
                            .Number => |num| {
                                if (isNextTemp) {
                                    isNextTemp = false;
                                    temp = @floatToInt(u16, std.math.round(try std.fmt.parseFloat(f32, num.slice(tokens.slice, tokens.i - 1))));
                                }
                                if (isNextCode) {
                                    isNextCode = false;
                                    code = try std.fmt.parseInt(i16, num.slice(tokens.slice, tokens.i - 1), 10);
                                }
                            },
                            else => {},
                        }
                    }
                },
                .status, .header, .head_complete, .closed, .end, .invalid => continue,
            }
        }
        return WeatherData{ .temp = temp, .main = main, .code = code, .message = message };
    }

    fn update_info(self: *WeatherWidget) anyerror!void {
        var inf: WeatherData = undefined;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var arenacator = &arena.allocator;
        if (self.get_weather_info(arenacator)) |i| {
            inf = i;
            //std.debug.print("{}", .{i});
        } else |err| switch (err) {
            error.TemporaryNameServerFailure => {
                try self.bar.add(Info{
                    .name = self.name,
                    .full_text = "DNS Error Fetching Weather",
                    .markup = "pango",
                });
            },
            error.InvalidIPAddressFormat => {
                try self.bar.add(Info{
                    .name = self.name,
                    .full_text = "Invalid Weather IP",
                    .markup = "pango",
                });
            },
            error.ConnectionResetByPeer => {
                try self.bar.add(Info{
                    .name = self.name,
                    .full_text = "Weather Reset",
                    .markup = "pango",
                });
            },
            else => |e| {
                std.debug.print("\n\n\n\n\nError!: {}\n\n\n\n\n", .{@errorName(e)});
                return;
            },
        }

        if (inf.code != 200) {
            try self.bar.add(Info{
                .name = self.name,
                .full_text = try std.fmt.allocPrint(arenacator, "Weather API Failed: {}", .{inf.message}),
                .markup = "pango",
            });
            return;
        }

        var temp = inf.temp;
        var main = inf.main;

        var tempColour: []const u8 = "green";
        if (temp >= 20) {
            tempColour = "red";
        } else if (temp >= 16) {
            tempColour = "orange";
        } else if (temp >= 12) {
            tempColour = "yellow";
        } else {
            tempColour = "green";
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
            std.time.sleep(30 * std.time.ns_per_min);
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
