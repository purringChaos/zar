name: []const u8 = "",
button: enum(u4) {
    LeftClick = 1,
    MiddleClick = 2,
    RightClick = 3,
    ScrollUp = 4,
    ScrollDown = 5,
    WheelLeft = 6,
    WheelRight = 7,
    Backwards = 8,
    Forwards = 9,
},
event: u16 = 0,
x: u16 = 0,
y: u16 = 0,
relative_x: u16 = 0,
relative_y: u16 = 0,
height: u16 = 0,
width: u16 = 0,