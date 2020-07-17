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

/// This colours a string but at comptime.
pub fn comptimeColour(comptime clr: []const u8, comptime str: []const u8) []const u8 {
    if (disable_colour) return str;

    if (clr[0] == '#' or clr[0] == '\u{001b}') {
        if (terminal_version) {
            return crl ++ str ++ TerminalResetColour;
        } else {
            return "<span color=\"" ++ clr ++ "\">" ++ str ++ "</span>";
        }
    } else {
        comptime var colourText: []const u8 = "";
        if (eql(u8, clr, "text")) {
            colourText = if (!terminal_version) TextColour else TerminalTextColour;
        } else if (eql(u8, clr, "dark")) {
            colourText = if (!terminal_version) DarkerTextColour else TerminalDarkerTextColour;
        } else if (eql(u8, clr, "darkest")) {
            colourText = if (!terminal_version) DarkestTextColour else TerminalDarkestTextColour;
        } else if (eql(u8, clr, "accentlight")) {
            colourText = if (!terminal_version) AccentLightColour else TerminalAccentLightColour;
        } else if (eql(u8, clr, "accentmedium")) {
            colourText = if (!terminal_version) AccentMediumColour else TerminalAccentMediumColour;
        } else if (eql(u8, clr, "accentdark")) {
            colourText = if (!terminal_version) AccentDarkColour else TerminalAccentDarkColour;
        } else if (eql(u8, clr, "red")) {
            colourText = if (!terminal_version) RedColour else TerminalRedColour;
        } else if (eql(u8, clr, "orange")) {
            colourText = if (!terminal_version) OrangeColour else TerminalOrangeColour;
        } else if (eql(u8, clr, "yellow")) {
            colourText = if (!terminal_version) YellowColour else TerminalYellowColour;
        } else if (eql(u8, clr, "green")) {
            colourText = if (!terminal_version) GreenColour else TerminalGreenColour;
        } else if (eql(u8, clr, "purple")) {
            colourText = if (!terminal_version) PurpleColour else TerminalPurpleColour;
        }
        if (colourText.len == 0) {
            unreachable;
        }
        return comptimeColour(colourText, str);
    }
}

/// This colours a dynamic string at runtime.
/// It may make more than one allocation,
/// so put it on a ArenaAllocator so you can free what else it allocates.
pub fn colour(alloc: *std.mem.Allocator, clr: []const u8, str: []const u8) ![]const u8 {
    if (disable_colour) return str;

    if (clr[0] == '#' or clr[0] == '\u{001b}') {
        if (terminal_version) {
            return try std.fmt.allocPrint(alloc, "{}{}" ++ TerminalResetColour, .{ clr, str });
        } else {
            return try std.fmt.allocPrint(alloc, "<span color=\"{}\">{}</span>", .{ clr, str });
        }
    } else {
        var colourText: []const u8 = "";
        if (eql(u8, clr, "text")) {
            colourText = if (!terminal_version) TextColour else TerminalTextColour;
        } else if (eql(u8, clr, "dark")) {
            colourText = if (!terminal_version) DarkerTextColour else TerminalDarkerTextColour;
        } else if (eql(u8, clr, "darkest")) {
            colourText = if (!terminal_version) DarkestTextColour else TerminalDarkestTextColour;
        } else if (eql(u8, clr, "accentlight")) {
            colourText = if (!terminal_version) AccentLightColour else TerminalAccentLightColour;
        } else if (eql(u8, clr, "accentmedium")) {
            colourText = if (!terminal_version) AccentMediumColour else TerminalAccentMediumColour;
        } else if (eql(u8, clr, "accentdark")) {
            colourText = if (!terminal_version) AccentDarkColour else TerminalAccentDarkColour;
        } else if (eql(u8, clr, "red")) {
            colourText = if (!terminal_version) RedColour else TerminalRedColour;
        } else if (eql(u8, clr, "orange")) {
            colourText = if (!terminal_version) OrangeColour else TerminalOrangeColour;
        } else if (eql(u8, clr, "yellow")) {
            colourText = if (!terminal_version) YellowColour else TerminalYellowColour;
        } else if (eql(u8, clr, "green")) {
            colourText = if (!terminal_version) GreenColour else TerminalGreenColour;
        } else if (eql(u8, clr, "purple")) {
            colourText = if (!terminal_version) PurpleColour else TerminalPurpleColour;
        }
        return colour(alloc, colourText, str);
    }
}
