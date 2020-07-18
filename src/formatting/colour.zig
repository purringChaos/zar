const std = @import("std");
const eql = std.mem.eql;
const terminal_version = @import("build_options").terminal_version;
const disable_colour = @import("build_options").disable_colour;

const TextColour = "#D8DEE9";
const DarkerTextColour = "#E5E9F0";
const DarkestTextColour = "#ECEFF4";
const AccentLightColour = "#88C0D0";
const AccentMediumColour = "#81A1C1";
const AccentDarkColour = "#5E81AC";
const RedColour = "#BF616A";
const OrangeColour = "#D08770";
const YellowColour = "#EBCB8B";
const GreenColour = "#A3BE8C";
const PurpleColour = "#B48EAD";

const TerminalResetColour = "\u{001b}[37m";
const TerminalTextColour = TerminalResetColour;
const TerminalDarkerTextColour = TerminalResetColour;
const TerminalDarkestTextColour = TerminalResetColour;
const TerminalAccentLightColour = "\u{001b}[38;5;38m";
const TerminalAccentMediumColour = "\u{001b}[38;5;32m";
const TerminalAccentDarkColour = "\u{001b}[38;5;26m";
const TerminalRedColour = "\u{001b}[31m";
const TerminalOrangeColour = "\u{001b}[31;1m";
const TerminalYellowColour = "\u{001b}[33m";
const TerminalGreenColour = "\u{001b}[32m";
const TerminalPurpleColour = "\u{001b}[35m";

inline fn getColourFromColour(clr: []const u8) []const u8 {
    if (clr[0] == '#' or clr[0] == '\u{001b}') {
        return clr;
    } else if (eql(u8, clr, "text")) {
        return if (!terminal_version) TextColour else TerminalTextColour;
    } else if (eql(u8, clr, "dark")) {
        return if (!terminal_version) DarkerTextColour else TerminalDarkerTextColour;
    } else if (eql(u8, clr, "darkest")) {
        return if (!terminal_version) DarkestTextColour else TerminalDarkestTextColour;
    } else if (eql(u8, clr, "accentlight")) {
        return if (!terminal_version) AccentLightColour else TerminalAccentLightColour;
    } else if (eql(u8, clr, "accentmedium")) {
        return if (!terminal_version) AccentMediumColour else TerminalAccentMediumColour;
    } else if (eql(u8, clr, "accentdark")) {
        return if (!terminal_version) AccentDarkColour else TerminalAccentDarkColour;
    } else if (eql(u8, clr, "red")) {
        return if (!terminal_version) RedColour else TerminalRedColour;
    } else if (eql(u8, clr, "orange")) {
        return if (!terminal_version) OrangeColour else TerminalOrangeColour;
    } else if (eql(u8, clr, "yellow")) {
        return if (!terminal_version) YellowColour else TerminalYellowColour;
    } else if (eql(u8, clr, "green")) {
        return if (!terminal_version) GreenColour else TerminalGreenColour;
    } else if (eql(u8, clr, "purple")) {
        return if (!terminal_version) PurpleColour else TerminalPurpleColour;
    } else {
        unreachable;
    }
}
/// This colours a string but at comptime.
pub fn comptimeColour(comptime clr: []const u8, comptime str: []const u8) []const u8 {
    if (disable_colour) return str;

    const proper_colour = comptime getColourFromColour(clr);
    if (terminal_version) {
        return proper_colour ++ str ++ TerminalResetColour;
    } else {
        return "<span color=\"" ++ proper_colour ++ "\">" ++ str ++ "</span>";
    }
}

/// This colours a dynamic string at runtime.
pub fn colour(alloc: *std.mem.Allocator, clr: []const u8, str: []const u8) ![]const u8 {
    if (disable_colour) return str;
    const proper_colour = getColourFromColour(clr);
    if (terminal_version) {
        return try std.fmt.allocPrint(alloc, "{}{}" ++ TerminalResetColour, .{ proper_colour, str });
    } else {
        return try std.fmt.allocPrint(alloc, "<span color=\"{}\">{}</span>", .{ proper_colour, str });
    }
}
