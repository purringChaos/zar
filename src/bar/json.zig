const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const maxInt = std.math.maxInt;
pub const WriteStream = @import("json/write_stream.zig").WriteStream;
pub const writeStream = @import("json/write_stream.zig").writeStream;
const StringEscapes = union(enum) {
    None,
    Some: struct {
        size_diff: isize,
    },
};
fn encodesTo(decoded: []const u8, encoded: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < decoded.len) {
        if (j >= encoded.len) return false;
        if (encoded[j] != '\\') {
            if (decoded[i] != encoded[j]) return false;
            j += 1;
            i += 1;
        } else {
            const escape_type = encoded[j + 1];
            if (escape_type != 'u') {
                const t: u8 = switch (escape_type) {
                    '\\' => '\\',
                    '/' => '/',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    'f' => 12,
                    'b' => 8,
                    '"' => '"',
                    else => unreachable,
                };
                if (decoded[i] != t) return false;
                j += 2;
                i += 1;
            } else {
                var codepoint = std.fmt.parseInt(u21, encoded[j + 2 .. j + 6], 16) catch unreachable;
                j += 6;
                if (codepoint >= 0xD800 and codepoint < 0xDC00) {
                    assert(encoded[j] == '\\');
                    assert(encoded[j + 1] == 'u');
                    const low_surrogate = std.fmt.parseInt(u21, encoded[j + 2 .. j + 6], 16) catch unreachable;
                    codepoint = 0x10000 + (((codepoint & 0x03ff) << 10) | (low_surrogate & 0x03ff));
                    j += 6;
                }
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(codepoint, &buf) catch unreachable;
                if (i + len > decoded.len) return false;
                if (!mem.eql(u8, decoded[i .. i + len], buf[0..len])) return false;
                i += len;
            }
        }
    }
    assert(i == decoded.len);
    assert(j == encoded.len);
    return true;
}
pub const Token = union(enum) {
    ObjectBegin,
    ObjectEnd,
    ArrayBegin,
    ArrayEnd,
    String: struct {
        count: usize,
        escapes: StringEscapes,
        pub fn decodedLength(self: @This()) usize {
            return self.count +% switch (self.escapes) {
                .None => 0,
                .Some => |s| @bitCast(usize, s.size_diff),
            };
        }
        pub fn slice(self: @This(), input: []const u8, i: usize) []const u8 {
            return input[i - self.count .. i];
        }
    },
    Number: struct {
        count: usize,
        is_integer: bool,
        pub fn slice(self: @This(), input: []const u8, i: usize) []const u8 {
            return input[i - self.count .. i];
        }
    },
    True,
    False,
    Null,
};
pub const StreamingParser = struct {
    state: State,
    count: usize,
    after_string_state: State,
    after_value_state: State,
    complete: bool,
    string_escapes: StringEscapes,
    string_last_was_high_surrogate: bool,
    string_unicode_codepoint: u21,
    sequence_first_byte: u8 = undefined,
    number_is_integer: bool,
    stack: u256,
    stack_used: u8,

    const object_bit = 0;
    const array_bit = 1;
    const max_stack_size = maxInt(u8);
    pub fn init() StreamingParser {
        var p: StreamingParser = undefined;
        p.reset();
        return p;
    }
    pub fn reset(p: *StreamingParser) void {
        p.state = .TopLevelBegin;
        p.count = 0;
        p.after_string_state = undefined;
        p.stack = 0;
        p.stack_used = 0;
        p.complete = false;
        p.string_escapes = undefined;
        p.string_last_was_high_surrogate = undefined;
        p.string_unicode_codepoint = undefined;
        p.number_is_integer = undefined;
    }
    pub const State = enum {
        ObjectSeparator = 0,
        ValueEnd = 1,
        TopLevelBegin,
        TopLevelEnd,
        ValueBegin,
        ValueBeginNoClosing,
        String,
        StringUtf8Byte2Of2,
        StringUtf8Byte2Of3,
        StringUtf8Byte3Of3,
        StringUtf8Byte2Of4,
        StringUtf8Byte3Of4,
        StringUtf8Byte4Of4,
        StringEscapeCharacter,
        StringEscapeHexUnicode4,
        StringEscapeHexUnicode3,
        StringEscapeHexUnicode2,
        StringEscapeHexUnicode1,
        Number,
        NumberMaybeDotOrExponent,
        NumberMaybeDigitOrDotOrExponent,
        NumberFractionalRequired,
        NumberFractional,
        NumberMaybeExponent,
        NumberExponent,
        NumberExponentDigitsRequired,
        NumberExponentDigits,
        TrueLiteral1,
        TrueLiteral2,
        TrueLiteral3,
        FalseLiteral1,
        FalseLiteral2,
        FalseLiteral3,
        FalseLiteral4,
        NullLiteral1,
        NullLiteral2,
        NullLiteral3,
        pub fn fromInt(x: anytype) State {
            debug.assert(x == 0 or x == 1);
            const T = @TagType(State);
            return @intToEnum(State, @intCast(T, x));
        }
    };
    pub const Error = error{
        InvalidTopLevel,
        TooManyNestedItems,
        TooManyClosingItems,
        InvalidValueBegin,
        InvalidValueEnd,
        UnbalancedBrackets,
        UnbalancedBraces,
        UnexpectedClosingBracket,
        UnexpectedClosingBrace,
        InvalidNumber,
        InvalidSeparator,
        InvalidLiteral,
        InvalidEscapeCharacter,
        InvalidUnicodeHexSymbol,
        InvalidUtf8Byte,
        InvalidTopLevelTrailing,
        InvalidControlCharacter,
    };
    pub fn feed(p: *StreamingParser, c: u8, token1: *?Token, token2: *?Token) Error!void {
        token1.* = null;
        token2.* = null;
        p.count += 1;
        if (try p.transition(c, token1)) {
            _ = try p.transition(c, token2);
        }
    }
    fn transition(p: *StreamingParser, c: u8, token: *?Token) Error!bool {
        switch (p.state) {
            .TopLevelBegin => switch (c) {
                '{' => {
                    p.stack <<= 1;
                    p.stack |= object_bit;
                    p.stack_used += 1;
                    p.state = .ValueBegin;
                    p.after_string_state = .ObjectSeparator;
                    token.* = Token.ObjectBegin;
                },
                '[' => {
                    p.stack <<= 1;
                    p.stack |= array_bit;
                    p.stack_used += 1;
                    p.state = .ValueBegin;
                    p.after_string_state = .ValueEnd;
                    token.* = Token.ArrayBegin;
                },
                '-' => {
                    p.number_is_integer = true;
                    p.state = .Number;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                '0' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDotOrExponent;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                '1'...'9' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDigitOrDotOrExponent;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                '"' => {
                    p.state = .String;
                    p.after_value_state = .TopLevelEnd;
                    p.after_string_state = .ValueEnd;
                    p.string_escapes = .None;
                    p.string_last_was_high_surrogate = false;
                    p.count = 0;
                },
                't' => {
                    p.state = .TrueLiteral1;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                'f' => {
                    p.state = .FalseLiteral1;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                'n' => {
                    p.state = .NullLiteral1;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                0x09, 0x0A, 0x0D, 0x20 => {},
                else => {
                    return error.InvalidTopLevel;
                },
            },
            .TopLevelEnd => switch (c) {
                0x09, 0x0A, 0x0D, 0x20 => {},
                else => {
                    return error.InvalidTopLevelTrailing;
                },
            },
            .ValueBegin => switch (c) {
                '}' => {
                    if (p.stack & 1 != object_bit) {
                        return error.UnexpectedClosingBracket;
                    }
                    if (p.stack_used == 0) {
                        return error.TooManyClosingItems;
                    }
                    p.state = .ValueBegin;
                    p.after_string_state = State.fromInt(p.stack & 1);
                    p.stack >>= 1;
                    p.stack_used -= 1;
                    switch (p.stack_used) {
                        0 => {
                            p.complete = true;
                            p.state = .TopLevelEnd;
                        },
                        else => {
                            p.state = .ValueEnd;
                        },
                    }
                    token.* = Token.ObjectEnd;
                },
                ']' => {
                    if (p.stack & 1 != array_bit) {
                        return error.UnexpectedClosingBrace;
                    }
                    if (p.stack_used == 0) {
                        return error.TooManyClosingItems;
                    }
                    p.state = .ValueBegin;
                    p.after_string_state = State.fromInt(p.stack & 1);
                    p.stack >>= 1;
                    p.stack_used -= 1;
                    switch (p.stack_used) {
                        0 => {
                            p.complete = true;
                            p.state = .TopLevelEnd;
                        },
                        else => {
                            p.state = .ValueEnd;
                        },
                    }
                    token.* = Token.ArrayEnd;
                },
                '{' => {
                    if (p.stack_used == max_stack_size) {
                        return error.TooManyNestedItems;
                    }
                    p.stack <<= 1;
                    p.stack |= object_bit;
                    p.stack_used += 1;
                    p.state = .ValueBegin;
                    p.after_string_state = .ObjectSeparator;
                    token.* = Token.ObjectBegin;
                },
                '[' => {
                    if (p.stack_used == max_stack_size) {
                        return error.TooManyNestedItems;
                    }
                    p.stack <<= 1;
                    p.stack |= array_bit;
                    p.stack_used += 1;
                    p.state = .ValueBegin;
                    p.after_string_state = .ValueEnd;
                    token.* = Token.ArrayBegin;
                },
                '-' => {
                    p.number_is_integer = true;
                    p.state = .Number;
                    p.count = 0;
                },
                '0' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDotOrExponent;
                    p.count = 0;
                },
                '1'...'9' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDigitOrDotOrExponent;
                    p.count = 0;
                },
                '"' => {
                    p.state = .String;
                    p.string_escapes = .None;
                    p.string_last_was_high_surrogate = false;
                    p.count = 0;
                },
                't' => {
                    p.state = .TrueLiteral1;
                    p.count = 0;
                },
                'f' => {
                    p.state = .FalseLiteral1;
                    p.count = 0;
                },
                'n' => {
                    p.state = .NullLiteral1;
                    p.count = 0;
                },
                0x09, 0x0A, 0x0D, 0x20 => {},
                else => {
                    return error.InvalidValueBegin;
                },
            },
            .ValueBeginNoClosing => switch (c) {
                '{' => {
                    if (p.stack_used == max_stack_size) {
                        return error.TooManyNestedItems;
                    }
                    p.stack <<= 1;
                    p.stack |= object_bit;
                    p.stack_used += 1;
                    p.state = .ValueBegin;
                    p.after_string_state = .ObjectSeparator;
                    token.* = Token.ObjectBegin;
                },
                '[' => {
                    if (p.stack_used == max_stack_size) {
                        return error.TooManyNestedItems;
                    }
                    p.stack <<= 1;
                    p.stack |= array_bit;
                    p.stack_used += 1;
                    p.state = .ValueBegin;
                    p.after_string_state = .ValueEnd;
                    token.* = Token.ArrayBegin;
                },
                '-' => {
                    p.number_is_integer = true;
                    p.state = .Number;
                    p.count = 0;
                },
                '0' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDotOrExponent;
                    p.count = 0;
                },
                '1'...'9' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDigitOrDotOrExponent;
                    p.count = 0;
                },
                '"' => {
                    p.state = .String;
                    p.string_escapes = .None;
                    p.string_last_was_high_surrogate = false;
                    p.count = 0;
                },
                't' => {
                    p.state = .TrueLiteral1;
                    p.count = 0;
                },
                'f' => {
                    p.state = .FalseLiteral1;
                    p.count = 0;
                },
                'n' => {
                    p.state = .NullLiteral1;
                    p.count = 0;
                },
                0x09, 0x0A, 0x0D, 0x20 => {},
                else => {
                    return error.InvalidValueBegin;
                },
            },
            .ValueEnd => switch (c) {
                ',' => {
                    p.after_string_state = State.fromInt(p.stack & 1);
                    p.state = .ValueBeginNoClosing;
                },
                ']' => {
                    if (p.stack_used == 0) {
                        return error.UnbalancedBrackets;
                    }
                    p.state = .ValueEnd;
                    p.after_string_state = State.fromInt(p.stack & 1);
                    p.stack >>= 1;
                    p.stack_used -= 1;
                    if (p.stack_used == 0) {
                        p.complete = true;
                        p.state = .TopLevelEnd;
                    }
                    token.* = Token.ArrayEnd;
                },
                '}' => {
                    if (p.stack_used == 0) {
                        return error.UnbalancedBraces;
                    }
                    p.state = .ValueEnd;
                    p.after_string_state = State.fromInt(p.stack & 1);
                    p.stack >>= 1;
                    p.stack_used -= 1;
                    if (p.stack_used == 0) {
                        p.complete = true;
                        p.state = .TopLevelEnd;
                    }
                    token.* = Token.ObjectEnd;
                },
                0x09, 0x0A, 0x0D, 0x20 => {},
                else => {
                    return error.InvalidValueEnd;
                },
            },
            .ObjectSeparator => switch (c) {
                ':' => {
                    p.state = .ValueBegin;
                    p.after_string_state = .ValueEnd;
                },
                0x09, 0x0A, 0x0D, 0x20 => {},
                else => {
                    return error.InvalidSeparator;
                },
            },
            .String => switch (c) {
                0x00...0x1F => {
                    return error.InvalidControlCharacter;
                },
                '"' => {
                    p.state = p.after_string_state;
                    if (p.after_value_state == .TopLevelEnd) {
                        p.state = .TopLevelEnd;
                        p.complete = true;
                    }
                    token.* = .{
                        .String = .{
                            .count = p.count - 1,
                            .escapes = p.string_escapes,
                        },
                    };
                    p.string_escapes = undefined;
                    p.string_last_was_high_surrogate = undefined;
                },
                '\\' => {
                    p.state = .StringEscapeCharacter;
                    switch (p.string_escapes) {
                        .None => {
                            p.string_escapes = .{ .Some = .{ .size_diff = 0 } };
                        },
                        .Some => {},
                    }
                },
                0x20, 0x21, 0x23...0x5B, 0x5D...0x7F => {
                    p.string_last_was_high_surrogate = false;
                },
                0xC2...0xDF => {
                    p.state = .StringUtf8Byte2Of2;
                },
                0xE0...0xEF => {
                    p.state = .StringUtf8Byte2Of3;
                    p.sequence_first_byte = c;
                },
                0xF0...0xF4 => {
                    p.state = .StringUtf8Byte2Of4;
                    p.sequence_first_byte = c;
                },
                else => {
                    return error.InvalidUtf8Byte;
                },
            },
            .StringUtf8Byte2Of2 => switch (c >> 6) {
                0b10 => p.state = .String,
                else => return error.InvalidUtf8Byte,
            },
            .StringUtf8Byte2Of3 => {
                switch (p.sequence_first_byte) {
                    0xE0 => switch (c) {
                        0xA0...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    0xE1...0xEF => switch (c) {
                        0x80...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    else => return error.InvalidUtf8Byte,
                }
                p.state = .StringUtf8Byte3Of3;
            },
            .StringUtf8Byte3Of3 => switch (c) {
                0x80...0xBF => p.state = .String,
                else => return error.InvalidUtf8Byte,
            },
            .StringUtf8Byte2Of4 => {
                switch (p.sequence_first_byte) {
                    0xF0 => switch (c) {
                        0x90...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    0xF1...0xF3 => switch (c) {
                        0x80...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    0xF4 => switch (c) {
                        0x80...0x8F => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    else => return error.InvalidUtf8Byte,
                }
                p.state = .StringUtf8Byte3Of4;
            },
            .StringUtf8Byte3Of4 => switch (c) {
                0x80...0xBF => p.state = .StringUtf8Byte4Of4,
                else => return error.InvalidUtf8Byte,
            },
            .StringUtf8Byte4Of4 => switch (c) {
                0x80...0xBF => p.state = .String,
                else => return error.InvalidUtf8Byte,
            },
            .StringEscapeCharacter => switch (c) {
                '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {
                    p.string_escapes.Some.size_diff -= 1;
                    p.state = .String;
                    p.string_last_was_high_surrogate = false;
                },
                'u' => {
                    p.state = .StringEscapeHexUnicode4;
                },
                else => {
                    return error.InvalidEscapeCharacter;
                },
            },
            .StringEscapeHexUnicode4 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .StringEscapeHexUnicode3;
                p.string_unicode_codepoint = codepoint << 12;
            },
            .StringEscapeHexUnicode3 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .StringEscapeHexUnicode2;
                p.string_unicode_codepoint |= codepoint << 8;
            },
            .StringEscapeHexUnicode2 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .StringEscapeHexUnicode1;
                p.string_unicode_codepoint |= codepoint << 4;
            },
            .StringEscapeHexUnicode1 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .String;
                p.string_unicode_codepoint |= codepoint;
                if (p.string_unicode_codepoint < 0xD800 or p.string_unicode_codepoint >= 0xE000) {
                    p.string_escapes.Some.size_diff -= @as(isize, 6 - (std.unicode.utf8CodepointSequenceLength(p.string_unicode_codepoint) catch unreachable));
                    p.string_last_was_high_surrogate = false;
                } else if (p.string_unicode_codepoint < 0xDC00) {
                    p.string_escapes.Some.size_diff -= 6 - 3;
                    p.string_last_was_high_surrogate = true;
                } else {
                    p.string_escapes.Some.size_diff -= 6;
                    if (p.string_last_was_high_surrogate) {
                        p.string_escapes.Some.size_diff -= -1;
                    } else {
                        p.string_escapes.Some.size_diff -= -3;
                    }
                    p.string_last_was_high_surrogate = false;
                }
                p.string_unicode_codepoint = undefined;
            },
            .Number => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0' => {
                        p.state = .NumberMaybeDotOrExponent;
                    },
                    '1'...'9' => {
                        p.state = .NumberMaybeDigitOrDotOrExponent;
                    },
                    else => {
                        return error.InvalidNumber;
                    },
                }
            },
            .NumberMaybeDotOrExponent => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '.' => {
                        p.number_is_integer = false;
                        p.state = .NumberFractionalRequired;
                    },
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        p.number_is_integer = undefined;
                        return true;
                    },
                }
            },
            .NumberMaybeDigitOrDotOrExponent => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '.' => {
                        p.number_is_integer = false;
                        p.state = .NumberFractionalRequired;
                    },
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    '0'...'9' => {},
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },
            .NumberFractionalRequired => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0'...'9' => {
                        p.state = .NumberFractional;
                    },
                    else => {
                        return error.InvalidNumber;
                    },
                }
            },
            .NumberFractional => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0'...'9' => {},
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },
            .NumberMaybeExponent => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },
            .NumberExponent => switch (c) {
                '-', '+' => {
                    p.complete = false;
                    p.state = .NumberExponentDigitsRequired;
                },
                '0'...'9' => {
                    p.complete = p.after_value_state == .TopLevelEnd;
                    p.state = .NumberExponentDigits;
                },
                else => {
                    return error.InvalidNumber;
                },
            },
            .NumberExponentDigitsRequired => switch (c) {
                '0'...'9' => {
                    p.complete = p.after_value_state == .TopLevelEnd;
                    p.state = .NumberExponentDigits;
                },
                else => {
                    return error.InvalidNumber;
                },
            },
            .NumberExponentDigits => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0'...'9' => {},
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },
            .TrueLiteral1 => switch (c) {
                'r' => p.state = .TrueLiteral2,
                else => return error.InvalidLiteral,
            },
            .TrueLiteral2 => switch (c) {
                'u' => p.state = .TrueLiteral3,
                else => return error.InvalidLiteral,
            },
            .TrueLiteral3 => switch (c) {
                'e' => {
                    p.state = p.after_value_state;
                    p.complete = p.state == .TopLevelEnd;
                    token.* = Token.True;
                },
                else => {
                    return error.InvalidLiteral;
                },
            },
            .FalseLiteral1 => switch (c) {
                'a' => p.state = .FalseLiteral2,
                else => return error.InvalidLiteral,
            },
            .FalseLiteral2 => switch (c) {
                'l' => p.state = .FalseLiteral3,
                else => return error.InvalidLiteral,
            },
            .FalseLiteral3 => switch (c) {
                's' => p.state = .FalseLiteral4,
                else => return error.InvalidLiteral,
            },
            .FalseLiteral4 => switch (c) {
                'e' => {
                    p.state = p.after_value_state;
                    p.complete = p.state == .TopLevelEnd;
                    token.* = Token.False;
                },
                else => {
                    return error.InvalidLiteral;
                },
            },
            .NullLiteral1 => switch (c) {
                'u' => p.state = .NullLiteral2,
                else => return error.InvalidLiteral,
            },
            .NullLiteral2 => switch (c) {
                'l' => p.state = .NullLiteral3,
                else => return error.InvalidLiteral,
            },
            .NullLiteral3 => switch (c) {
                'l' => {
                    p.state = p.after_value_state;
                    p.complete = p.state == .TopLevelEnd;
                    token.* = Token.Null;
                },
                else => {
                    return error.InvalidLiteral;
                },
            },
        }
        return false;
    }
};
pub const TokenStream = struct {
    i: usize,
    slice: []const u8,
    parser: StreamingParser,
    token: ?Token,
    pub const Error = StreamingParser.Error || error{UnexpectedEndOfJson};
    pub fn init(slice: []const u8) TokenStream {
        return TokenStream{
            .i = 0,
            .slice = slice,
            .parser = StreamingParser.init(),
            .token = null,
        };
    }
    pub fn next(self: *TokenStream) Error!?Token {
        if (self.token) |token| {
            self.token = null;
            return token;
        }
        var t1: ?Token = undefined;
        var t2: ?Token = undefined;
        while (self.i < self.slice.len) {
            try self.parser.feed(self.slice[self.i], &t1, &t2);
            self.i += 1;
            if (t1) |token| {
                self.token = t2;
                return token;
            }
        }
        try self.parser.feed(' ', &t1, &t2);
        self.i += 1;
        if (t1) |token| {
            return token;
        } else if (self.parser.complete) {
            return null;
        } else {
            return error.UnexpectedEndOfJson;
        }
    }
};
fn checkNext(p: *TokenStream, id: std.meta.TagType(Token)) void {
    const token = (p.next() catch unreachable).?;
    debug.assert(std.meta.activeTag(token) == id);
}
pub fn validate(s: []const u8) bool {
    var p = StreamingParser.init();
    for (s) |c, i| {
        var token1: ?Token = undefined;
        var token2: ?Token = undefined;
        p.feed(c, &token1, &token2) catch |err| {
            return false;
        };
    }
    return p.complete;
}
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
pub const ValueTree = struct {
    arena: ArenaAllocator,
    root: Value,
    pub fn deinit(self: *ValueTree) void {
        self.arena.deinit();
    }
};
pub const ObjectMap = StringHashMap(Value);
pub const Array = ArrayList(Value);
pub const Value = union(enum) {
    Null,
    Bool: bool,
    Integer: i64,
    Float: f64,
    String: []const u8,
    Array: Array,
    Object: ObjectMap,
    pub fn jsonStringify(
        value: @This(),
        options: StringifyOptions,
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        switch (value) {
            .Null => try stringify(null, options, out_stream),
            .Bool => |inner| try stringify(inner, options, out_stream),
            .Integer => |inner| try stringify(inner, options, out_stream),
            .Float => |inner| try stringify(inner, options, out_stream),
            .String => |inner| try stringify(inner, options, out_stream),
            .Array => |inner| try stringify(inner.span(), options, out_stream),
            .Object => |inner| {
                try out_stream.writeByte('{');
                var field_output = false;
                var child_options = options;
                if (child_options.whitespace) |*child_whitespace| {
                    child_whitespace.indent_level += 1;
                }
                var it = inner.iterator();
                while (it.next()) |entry| {
                    if (!field_output) {
                        field_output = true;
                    } else {
                        try out_stream.writeByte(',');
                    }
                    if (child_options.whitespace) |child_whitespace| {
                        try out_stream.writeByte('\n');
                        try child_whitespace.outputIndent(out_stream);
                    }
                    try stringify(entry.key, options, out_stream);
                    try out_stream.writeByte(':');
                    if (child_options.whitespace) |child_whitespace| {
                        if (child_whitespace.separator) {
                            try out_stream.writeByte(' ');
                        }
                    }
                    try stringify(entry.value, child_options, out_stream);
                }
                if (field_output) {
                    if (options.whitespace) |whitespace| {
                        try out_stream.writeByte('\n');
                        try whitespace.outputIndent(out_stream);
                    }
                }
                try out_stream.writeByte('}');
            },
        }
    }
    pub fn dump(self: Value) void {
        var held = std.debug.getStderrMutex().acquire();
        defer held.release();
        const stderr = io.getStdErr().writer();
        std.json.stringify(self, std.json.StringifyOptions{ .whitespace = null }, stderr) catch return;
    }
};
pub const ParseOptions = struct {
    allocator: ?*Allocator = null,
    duplicate_field_behavior: enum {
        UseFirst,
        Error,
        UseLast,
    } = .Error,
};
fn parseInternal(comptime T: type, token: Token, tokens: *TokenStream, options: ParseOptions) !T {
    switch (@typeInfo(T)) {
        .Bool => {
            return switch (token) {
                .True => true,
                .False => false,
                else => error.UnexpectedToken,
            };
        },
        .Float, .ComptimeFloat => {
            const numberToken = switch (token) {
                .Number => |n| n,
                else => return error.UnexpectedToken,
            };
            return try std.fmt.parseFloat(T, numberToken.slice(tokens.slice, tokens.i - 1));
        },
        .Int, .ComptimeInt => {
            const numberToken = switch (token) {
                .Number => |n| n,
                else => return error.UnexpectedToken,
            };
            if (!numberToken.is_integer) return error.UnexpectedToken;
            return try std.fmt.parseInt(T, numberToken.slice(tokens.slice, tokens.i - 1), 10);
        },
        .Optional => |optionalInfo| {
            if (token == .Null) {
                return null;
            } else {
                return try parseInternal(optionalInfo.child, token, tokens, options);
            }
        },
        .Enum => |enumInfo| {
            switch (token) {
                .Number => |numberToken| {
                    if (!numberToken.is_integer) return error.UnexpectedToken;
                    const n = try std.fmt.parseInt(enumInfo.tag_type, numberToken.slice(tokens.slice, tokens.i - 1), 10);
                    return try std.meta.intToEnum(T, n);
                },
                .String => |stringToken| {
                    const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                    switch (stringToken.escapes) {
                        .None => return std.meta.stringToEnum(T, source_slice) orelse return error.InvalidEnumTag,
                        .Some => {
                            inline for (enumInfo.fields) |field| {
                                if (field.name.len == stringToken.decodedLength() and encodesTo(field.name, source_slice)) {
                                    return @field(T, field.name);
                                }
                            }
                            return error.InvalidEnumTag;
                        },
                    }
                },
                else => return error.UnexpectedToken,
            }
        },
        .Union => |unionInfo| {
            if (unionInfo.tag_type) |_| {
                inline for (unionInfo.fields) |u_field| {
                    var tokens_copy = tokens.*;
                    if (parseInternal(u_field.field_type, token, &tokens_copy, options)) |value| {
                        tokens.* = tokens_copy;
                        return @unionInit(T, u_field.name, value);
                    } else |err| {
                        if (@as(@TypeOf(err) || error{OutOfMemory}, err) == error.OutOfMemory) return err;
                    }
                }
                return error.NoUnionMembersMatched;
            } else {
                @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        .Struct => |structInfo| {
            switch (token) {
                .ObjectBegin => {},
                else => return error.UnexpectedToken,
            }
            var r: T = undefined;
            var fields_seen = [_]bool{false} ** structInfo.fields.len;
            errdefer {
                inline for (structInfo.fields) |field, i| {
                    if (fields_seen[i]) {
                        parseFree(field.field_type, @field(r, field.name), options);
                    }
                }
            }
            while (true) {
                switch ((try tokens.next()) orelse return error.UnexpectedEndOfJson) {
                    .ObjectEnd => break,
                    .String => |stringToken| {
                        const key_source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                        var found = false;
                        inline for (structInfo.fields) |field, i| {
                            if ((stringToken.escapes == .None and mem.eql(u8, field.name, key_source_slice)) or (stringToken.escapes == .Some and (field.name.len == stringToken.decodedLength() and encodesTo(field.name, key_source_slice)))) {
                                if (fields_seen[i]) {
                                    if (options.duplicate_field_behavior == .UseFirst) {
                                        break;
                                    } else if (options.duplicate_field_behavior == .Error) {
                                        return error.DuplicateJSONField;
                                    } else if (options.duplicate_field_behavior == .UseLast) {
                                        parseFree(field.field_type, @field(r, field.name), options);
                                    }
                                }
                                @field(r, field.name) = try parse(field.field_type, tokens, options);
                                fields_seen[i] = true;
                                found = true;
                                break;
                            }
                        }
                        if (!found) return error.UnknownField;
                    },
                    else => return error.UnexpectedToken,
                }
            }
            inline for (structInfo.fields) |field, i| {
                if (!fields_seen[i]) {
                    if (field.default_value) |default| {
                        @field(r, field.name) = default;
                    } else {
                        return error.MissingField;
                    }
                }
            }
            return r;
        },
        .Array => |arrayInfo| {
            switch (token) {
                .ArrayBegin => {
                    var r: T = undefined;
                    var i: usize = 0;
                    errdefer {
                        while (true) : (i -= 1) {
                            parseFree(arrayInfo.child, r[i], options);
                            if (i == 0) break;
                        }
                    }
                    while (i < r.len) : (i += 1) {
                        r[i] = try parse(arrayInfo.child, tokens, options);
                    }
                    const tok = (try tokens.next()) orelse return error.UnexpectedEndOfJson;
                    switch (tok) {
                        .ArrayEnd => {},
                        else => return error.UnexpectedToken,
                    }
                    return r;
                },
                .String => |stringToken| {
                    if (arrayInfo.child != u8) return error.UnexpectedToken;
                    var r: T = undefined;
                    const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                    switch (stringToken.escapes) {
                        .None => mem.copy(u8, &r, source_slice),
                        .Some => try unescapeString(&r, source_slice),
                    }
                    return r;
                },
                else => return error.UnexpectedToken,
            }
        },
        .Pointer => |ptrInfo| {
            const allocator = options.allocator orelse return error.AllocatorRequired;
            switch (ptrInfo.size) {
                .One => {
                    const r: T = try allocator.create(ptrInfo.child);
                    r.* = try parseInternal(ptrInfo.child, token, tokens, options);
                    return r;
                },
                .Slice => {
                    switch (token) {
                        .ArrayBegin => {
                            var arraylist = std.ArrayList(ptrInfo.child).init(allocator);
                            errdefer {
                                while (arraylist.popOrNull()) |v| {
                                    parseFree(ptrInfo.child, v, options);
                                }
                                arraylist.deinit();
                            }
                            while (true) {
                                const tok = (try tokens.next()) orelse return error.UnexpectedEndOfJson;
                                switch (tok) {
                                    .ArrayEnd => break,
                                    else => {},
                                }
                                try arraylist.ensureCapacity(arraylist.items.len + 1);
                                const v = try parseInternal(ptrInfo.child, tok, tokens, options);
                                arraylist.appendAssumeCapacity(v);
                            }
                            return arraylist.toOwnedSlice();
                        },
                        .String => |stringToken| {
                            if (ptrInfo.child != u8) return error.UnexpectedToken;
                            const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                            switch (stringToken.escapes) {
                                .None => return allocator.dupe(u8, source_slice),
                                .Some => |some_escapes| {
                                    const output = try allocator.alloc(u8, stringToken.decodedLength());
                                    errdefer allocator.free(output);
                                    try unescapeString(output, source_slice);
                                    return output;
                                },
                            }
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
            }
        },
        else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}
pub fn parse(comptime T: type, tokens: *TokenStream, options: ParseOptions) !T {
    const token = (try tokens.next()) orelse return error.UnexpectedEndOfJson;
    return parseInternal(T, token, tokens, options);
}
pub fn parseFree(comptime T: type, value: T, options: ParseOptions) void {
    switch (@typeInfo(T)) {
        .Bool, .Float, .ComptimeFloat, .Int, .ComptimeInt, .Enum => {},
        .Optional => {
            if (value) |v| {
                return parseFree(@TypeOf(v), v, options);
            }
        },
        .Union => |unionInfo| {
            if (unionInfo.tag_type) |UnionTagType| {
                inline for (unionInfo.fields) |u_field| {
                    if (@enumToInt(@as(UnionTagType, value)) == u_field.enum_field.?.value) {
                        parseFree(u_field.field_type, @field(value, u_field.name), options);
                        break;
                    }
                }
            } else {
                unreachable;
            }
        },
        .Struct => |structInfo| {
            inline for (structInfo.fields) |field| {
                parseFree(field.field_type, @field(value, field.name), options);
            }
        },
        .Array => |arrayInfo| {
            for (value) |v| {
                parseFree(arrayInfo.child, v, options);
            }
        },
        .Pointer => |ptrInfo| {
            const allocator = options.allocator orelse unreachable;
            switch (ptrInfo.size) {
                .One => {
                    parseFree(ptrInfo.child, value.*, options);
                    allocator.destroy(value);
                },
                .Slice => {
                    for (value) |v| {
                        parseFree(ptrInfo.child, v, options);
                    }
                    allocator.free(value);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}
pub const Parser = struct {
    allocator: *Allocator,
    state: State,
    copy_strings: bool,
    stack: Array,
    const State = enum {
        ObjectKey,
        ObjectValue,
        ArrayValue,
        Simple,
    };
    pub fn init(allocator: *Allocator, copy_strings: bool) Parser {
        return Parser{
            .allocator = allocator,
            .state = .Simple,
            .copy_strings = copy_strings,
            .stack = Array.init(allocator),
        };
    }
    pub fn deinit(p: *Parser) void {
        p.stack.deinit();
    }
    pub fn reset(p: *Parser) void {
        p.state = .Simple;
        p.stack.shrink(0);
    }
    pub fn parse(p: *Parser, input: []const u8) !ValueTree {
        var s = TokenStream.init(input);
        var arena = ArenaAllocator.init(p.allocator);
        errdefer arena.deinit();
        while (try s.next()) |token| {
            try p.transition(&arena.allocator, input, s.i - 1, token);
        }
        debug.assert(p.stack.items.len == 1);
        return ValueTree{
            .arena = arena,
            .root = p.stack.items[0],
        };
    }
    fn transition(p: *Parser, allocator: *Allocator, input: []const u8, i: usize, token: Token) !void {
        switch (p.state) {
            .ObjectKey => switch (token) {
                .ObjectEnd => {
                    if (p.stack.items.len == 1) {
                        return;
                    }
                    var value = p.stack.pop();
                    try p.pushToParent(&value);
                },
                .String => |s| {
                    try p.stack.append(try p.parseString(allocator, s, input, i));
                    p.state = .ObjectValue;
                },
                else => {
                    return error.InvalidLiteral;
                },
            },
            .ObjectValue => {
                var object = &p.stack.items[p.stack.items.len - 2].Object;
                var key = p.stack.items[p.stack.items.len - 1].String;
                switch (token) {
                    .ObjectBegin => {
                        try p.stack.append(Value{ .Object = ObjectMap.init(allocator) });
                        p.state = .ObjectKey;
                    },
                    .ArrayBegin => {
                        try p.stack.append(Value{ .Array = Array.init(allocator) });
                        p.state = .ArrayValue;
                    },
                    .String => |s| {
                        _ = try object.put(key, try p.parseString(allocator, s, input, i));
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .Number => |n| {
                        _ = try object.put(key, try p.parseNumber(n, input, i));
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .True => {
                        _ = try object.put(key, Value{ .Bool = true });
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .False => {
                        _ = try object.put(key, Value{ .Bool = false });
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .Null => {
                        _ = try object.put(key, Value.Null);
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .ObjectEnd, .ArrayEnd => {
                        unreachable;
                    },
                }
            },
            .ArrayValue => {
                var array = &p.stack.items[p.stack.items.len - 1].Array;
                switch (token) {
                    .ArrayEnd => {
                        if (p.stack.items.len == 1) {
                            return;
                        }
                        var value = p.stack.pop();
                        try p.pushToParent(&value);
                    },
                    .ObjectBegin => {
                        try p.stack.append(Value{ .Object = ObjectMap.init(allocator) });
                        p.state = .ObjectKey;
                    },
                    .ArrayBegin => {
                        try p.stack.append(Value{ .Array = Array.init(allocator) });
                        p.state = .ArrayValue;
                    },
                    .String => |s| {
                        try array.append(try p.parseString(allocator, s, input, i));
                    },
                    .Number => |n| {
                        try array.append(try p.parseNumber(n, input, i));
                    },
                    .True => {
                        try array.append(Value{ .Bool = true });
                    },
                    .False => {
                        try array.append(Value{ .Bool = false });
                    },
                    .Null => {
                        try array.append(Value.Null);
                    },
                    .ObjectEnd => {
                        unreachable;
                    },
                }
            },
            .Simple => switch (token) {
                .ObjectBegin => {
                    try p.stack.append(Value{ .Object = ObjectMap.init(allocator) });
                    p.state = .ObjectKey;
                },
                .ArrayBegin => {
                    try p.stack.append(Value{ .Array = Array.init(allocator) });
                    p.state = .ArrayValue;
                },
                .String => |s| {
                    try p.stack.append(try p.parseString(allocator, s, input, i));
                },
                .Number => |n| {
                    try p.stack.append(try p.parseNumber(n, input, i));
                },
                .True => {
                    try p.stack.append(Value{ .Bool = true });
                },
                .False => {
                    try p.stack.append(Value{ .Bool = false });
                },
                .Null => {
                    try p.stack.append(Value.Null);
                },
                .ObjectEnd, .ArrayEnd => {
                    unreachable;
                },
            },
        }
    }
    fn pushToParent(p: *Parser, value: *const Value) !void {
        switch (p.stack.span()[p.stack.items.len - 1]) {
            Value.String => |key| {
                _ = p.stack.pop();
                var object = &p.stack.items[p.stack.items.len - 1].Object;
                _ = try object.put(key, value.*);
                p.state = .ObjectKey;
            },
            Value.Array => |*array| {
                try array.append(value.*);
                p.state = .ArrayValue;
            },
            else => {
                unreachable;
            },
        }
    }
    fn parseString(p: *Parser, allocator: *Allocator, s: std.meta.TagPayloadType(Token, Token.String), input: []const u8, i: usize) !Value {
        const slice = s.slice(input, i);
        switch (s.escapes) {
            .None => return Value{ .String = if (p.copy_strings) try allocator.dupe(u8, slice) else slice },
            .Some => |some_escapes| {
                const output = try allocator.alloc(u8, s.decodedLength());
                errdefer allocator.free(output);
                try unescapeString(output, slice);
                return Value{ .String = output };
            },
        }
    }
    fn parseNumber(p: *Parser, n: std.meta.TagPayloadType(Token, Token.Number), input: []const u8, i: usize) !Value {
        return if (n.is_integer)
            Value{ .Integer = try std.fmt.parseInt(i64, n.slice(input, i), 10) }
        else
            Value{ .Float = try std.fmt.parseFloat(f64, n.slice(input, i)) };
    }
};
fn unescapeString(output: []u8, input: []const u8) !void {
    var inIndex: usize = 0;
    var outIndex: usize = 0;
    while (inIndex < input.len) {
        if (input[inIndex] != '\\') {
            output[outIndex] = input[inIndex];
            inIndex += 1;
            outIndex += 1;
        } else if (input[inIndex + 1] != 'u') {
            output[outIndex] = @as(u8, switch (input[inIndex + 1]) {
                '\\' => '\\',
                '/' => '/',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'f' => 12,
                'b' => 8,
                '"' => '"',
                else => unreachable,
            });
            inIndex += 2;
            outIndex += 1;
        } else {
            const firstCodeUnit = std.fmt.parseInt(u16, input[inIndex + 2 .. inIndex + 6], 16) catch unreachable;
            if (std.unicode.utf8Encode(firstCodeUnit, output[outIndex..])) |byteCount| {
                outIndex += byteCount;
                inIndex += 6;
            } else |err| {
                if (err != error.Utf8CannotEncodeSurrogateHalf) {
                    return error.InvalidUnicodeHexSymbol;
                }
                if (inIndex + 7 >= input.len or input[inIndex + 6] != '\\' or input[inIndex + 7] != 'u') {
                    return error.InvalidUnicodeHexSymbol;
                }
                const secondCodeUnit = std.fmt.parseInt(u16, input[inIndex + 8 .. inIndex + 12], 16) catch unreachable;
                if (std.unicode.utf16leToUtf8(output[outIndex..], &[2]u16{ firstCodeUnit, secondCodeUnit })) |byteCount| {
                    outIndex += byteCount;
                    inIndex += 12;
                } else |_| {
                    return error.InvalidUnicodeHexSymbol;
                }
            }
        }
    }
    assert(outIndex == output.len);
}
pub const StringifyOptions = struct {
    pub const Whitespace = struct {
        indent_level: usize = 0,
        indent: union(enum) {
            Space: u8,
            Tab: void,
        } = .{ .Space = 4 },
        separator: bool = true,
        pub fn outputIndent(
            whitespace: @This(),
            out_stream: anytype,
        ) @TypeOf(out_stream).Error!void {
            var char: u8 = undefined;
            var n_chars: usize = undefined;
            switch (whitespace.indent) {
                .Space => |n_spaces| {
                    char = ' ';
                    n_chars = n_spaces;
                },
                .Tab => {
                    char = '\t';
                    n_chars = 1;
                },
            }
            n_chars *= whitespace.indent_level;
            try out_stream.writeByteNTimes(char, n_chars);
        }
    };
    whitespace: ?Whitespace = null,
    string: StringOptions = StringOptions{ .String = .{} },
    pub const StringOptions = union(enum) {
        Array,
        String: StringOutputOptions,
        const StringOutputOptions = struct {
            escape_solidus: bool = false,
            escape_unicode: bool = false,
        };
    };
};
fn outputUnicodeEscape(
    codepoint: u21,
    out_stream: anytype,
) !void {
    if (codepoint <= 0xFFFF) {
        try out_stream.writeAll("\\u");
        try std.fmt.formatIntValue(codepoint, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, out_stream);
    } else {
        assert(codepoint <= 0x10FFFF);
        const high = @intCast(u16, (codepoint - 0x10000) >> 10) + 0xD800;
        const low = @intCast(u16, codepoint & 0x3FF) + 0xDC00;
        try out_stream.writeAll("\\u");
        try std.fmt.formatIntValue(high, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, out_stream);
        try out_stream.writeAll("\\u");
        try std.fmt.formatIntValue(low, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, out_stream);
    }
}
pub fn stringify(
    value: anytype,
    options: StringifyOptions,
    out_stream: anytype,
) @TypeOf(out_stream).Error!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => {
            return std.fmt.formatFloatScientific(value, std.fmt.FormatOptions{}, out_stream);
        },
        .Int, .ComptimeInt => {
            return std.fmt.formatIntValue(value, "", std.fmt.FormatOptions{}, out_stream);
        },
        .Bool => {
            return out_stream.writeAll(if (value) "true" else "false");
        },
        .Null => {
            return out_stream.writeAll("null");
        },
        .Optional => {
            if (value) |payload| {
                return try stringify(payload, options, out_stream);
            } else {
                return try stringify(null, options, out_stream);
            }
        },
        .Enum => {
            if (comptime std.meta.trait.hasFn("jsonStringify")(T)) {
                return value.jsonStringify(options, out_stream);
            }
            @compileError("Unable to stringify enum '" ++ @typeName(T) ++ "'");
        },
        .Union => {
            if (comptime std.meta.trait.hasFn("jsonStringify")(T)) {
                return value.jsonStringify(options, out_stream);
            }
            const info = @typeInfo(T).Union;
            if (info.tag_type) |UnionTagType| {
                inline for (info.fields) |u_field| {
                    if (@enumToInt(@as(UnionTagType, value)) == u_field.enum_field.?.value) {
                        return try stringify(@field(value, u_field.name), options, out_stream);
                    }
                }
            } else {
                @compileError("Unable to stringify untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        .Struct => |S| {
            if (comptime std.meta.trait.hasFn("jsonStringify")(T)) {
                return value.jsonStringify(options, out_stream);
            }
            try out_stream.writeByte('{');
            comptime var field_output = false;
            var child_options = options;
            if (child_options.whitespace) |*child_whitespace| {
                child_whitespace.indent_level += 1;
            }
            inline for (S.fields) |Field, field_i| {
                if (Field.field_type == void) continue;
                if (!field_output) {
                    field_output = true;
                } else {
                    try out_stream.writeByte(',');
                }
                if (child_options.whitespace) |child_whitespace| {
                    try out_stream.writeByte('\n');
                    try child_whitespace.outputIndent(out_stream);
                }
                try stringify(Field.name, options, out_stream);
                try out_stream.writeByte(':');
                if (child_options.whitespace) |child_whitespace| {
                    if (child_whitespace.separator) {
                        try out_stream.writeByte(' ');
                    }
                }
                try stringify(@field(value, Field.name), child_options, out_stream);
            }
            if (field_output) {
                if (options.whitespace) |whitespace| {
                    try out_stream.writeByte('\n');
                    try whitespace.outputIndent(out_stream);
                }
            }
            try out_stream.writeByte('}');
            return;
        },
        .ErrorSet => return stringify(@as([]const u8, @errorName(value)), options, out_stream),
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array => {
                    const Slice = []const std.meta.Elem(ptr_info.child);
                    return stringify(@as(Slice, value), options, out_stream);
                },
                else => {
                    return stringify(value.*, options, out_stream);
                },
            },
            .Slice => {
                if (ptr_info.child == u8 and options.string == .String) {
                    try out_stream.writeByte('\"');
                    var i: usize = 0;
                    while (i < value.len) : (i += 1) {
                        switch (value[i]) {
                            0x20...0x21, 0x23...0x2E, 0x30...0x5B, 0x5D...0x7F => |c| try out_stream.writeByte(c),
                            '\\' => try out_stream.writeAll("\\\\"),
                            '\"' => try out_stream.writeAll("\\\""),
                            '/' => {
                                if (options.string.String.escape_solidus) {
                                    try out_stream.writeAll("\\/");
                                } else {
                                    try out_stream.writeByte('/');
                                }
                            },
                            0x8 => try out_stream.writeAll("\\b"),
                            0xC => try out_stream.writeAll("\\f"),
                            '\n' => try out_stream.writeAll("\\n"),
                            '\r' => try out_stream.writeAll("\\r"),
                            '\t' => try out_stream.writeAll("\\t"),
                            else => {
                                const ulen = std.unicode.utf8ByteSequenceLength(value[i]) catch unreachable;
                                if (ulen == 1 or options.string.String.escape_unicode) {
                                    const codepoint = std.unicode.utf8Decode(value[i .. i + ulen]) catch unreachable;
                                    try outputUnicodeEscape(codepoint, out_stream);
                                } else {
                                    try out_stream.writeAll(value[i .. i + ulen]);
                                }
                                i += ulen - 1;
                            },
                        }
                    }
                    try out_stream.writeByte('\"');
                    return;
                }
                try out_stream.writeByte('[');
                var child_options = options;
                if (child_options.whitespace) |*whitespace| {
                    whitespace.indent_level += 1;
                }
                for (value) |x, i| {
                    if (i != 0) {
                        try out_stream.writeByte(',');
                    }
                    if (child_options.whitespace) |child_whitespace| {
                        try out_stream.writeByte('\n');
                        try child_whitespace.outputIndent(out_stream);
                    }
                    try stringify(x, child_options, out_stream);
                }
                if (value.len != 0) {
                    if (options.whitespace) |whitespace| {
                        try out_stream.writeByte('\n');
                        try whitespace.outputIndent(out_stream);
                    }
                }
                try out_stream.writeByte(']');
                return;
            },
            else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
        },
        .Array => return stringify(&value, options, out_stream),
        .Vector => |info| {
            const array: [info.len]info.child = value;
            return stringify(&array, options, out_stream);
        },
        else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}
fn teststringify(expected: []const u8, value: anytype, options: StringifyOptions) !void {
    const ValidationOutStream = struct {
        const Self = @This();
        pub const OutStream = std.io.OutStream(*Self, Error, write);
        pub const Error = error{
            TooMuchData,
            DifferentData,
        };
        expected_remaining: []const u8,
        fn init(exp: []const u8) Self {
            return .{ .expected_remaining = exp };
        }
        pub fn outStream(self: *Self) OutStream {
            return .{ .context = self };
        }
        fn write(self: *Self, bytes: []const u8) Error!usize {
            if (self.expected_remaining.len < bytes.len) {
                std.debug.warn(
                    \\====== expected this output: =========
                    \\{}
                    \\======== instead found this: =========
                    \\{}
                    \\======================================
                , .{
                    self.expected_remaining,
                    bytes,
                });
                return error.TooMuchData;
            }
            if (!mem.eql(u8, self.expected_remaining[0..bytes.len], bytes)) {
                std.debug.warn(
                    \\====== expected this output: =========
                    \\{}
                    \\======== instead found this: =========
                    \\{}
                    \\======================================
                , .{
                    self.expected_remaining[0..bytes.len],
                    bytes,
                });
                return error.DifferentData;
            }
            self.expected_remaining = self.expected_remaining[bytes.len..];
            return bytes.len;
        }
    };
    var vos = ValidationOutStream.init(expected);
    try stringify(value, options, vos.outStream());
    if (vos.expected_remaining.len > 0) return error.NotEnoughData;
}
