const std = @import("std");
const eql = std.mem.eql;

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

pub fn colour(alloc: *std.mem.Allocator, clr: []const u8, str: []const u8) ![]const u8 {
    if (clr[0] == '#') {
        return try std.fmt.allocPrint(alloc, "<span color=\"{}\">{}</span>", .{ clr, str });
    } else {
        if (eql(u8, clr, "text")) {
            return colour(alloc, TextColour, str);
        } else if (eql(u8, clr, "dark")) {
            return colour(alloc, DarkerTextColour, str);
        } else if (eql(u8, clr, "darkest")) {
            return colour(alloc, DarkestTextColour, str);
        } else if (eql(u8, clr, "accentlight")) {
            return colour(alloc, AccentLightColour, str);
        } else if (eql(u8, clr, "accentmedium")) {
            return colour(alloc, AccentMediumColour, str);
        } else if (eql(u8, clr, "accentdark")) {
            return colour(alloc, AccentDarkColour, str);
        } else if (eql(u8, clr, "red")) {
            return colour(alloc, RedColour, str);
        } else if (eql(u8, clr, "orange")) {
            return colour(alloc, OrangeColour, str);
        } else if (eql(u8, clr, "yellow")) {
            return colour(alloc, YellowColour, str);
        } else if (eql(u8, clr, "green")) {
            return colour(alloc, GreenColour, str);
        } else if (eql(u8, clr, "purple")) {
            return colour(alloc, PurpleColour, str);
        } else {
            return "what";
        }
    }
}
