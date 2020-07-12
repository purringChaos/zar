pub const MouseEvent = struct {
    name: []const u8,
    button: enum(u3) {
        LeftClick = 1,
        MiddleClick = 2,
        RightClick = 3,
        ScrollUp = 4,
        ScrollDown = 5,
    },
    event: u16,
    x: u16,
    y: u16,
    relative_x: u16,
    relative_y: u16,
    height: u16,
    width: u16,
};
