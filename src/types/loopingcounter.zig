const std = @import("std");
const testing = std.testing;

pub fn LoopingCounter(
    comptime max_number: comptime_int,
) type {
    return struct {
        const Self = @This();
        i: std.math.IntFittingRange(0, max_number) = 0,
        n: std.math.IntFittingRange(0, max_number) = max_number,
        pub fn init() Self {
            return .{};
        }
        pub fn get(s: *Self) std.math.IntFittingRange(0, max_number) {
            return s.i;
        }
        pub fn next(s: *Self) void {
            if (s.i == s.n) {
                s.i = 0;
            } else {
                s.i = s.i + 1;
            }
        }
    };
}

test "looping test" {
    var lc = LoopingCounter(3).init();
    testing.expect(lc.get() == 0);
    lc.next();
    testing.expect(lc.get() != 0);
    testing.expect(lc.get() == 1);
    lc.next();
    testing.expect(lc.get() == 2);
    lc.next();
    testing.expect(lc.get() == 3);
    lc.next();
    testing.expect(lc.get() == 0);
}
