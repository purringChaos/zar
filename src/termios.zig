const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const linux = os.linux;
const assert = std.debug.assert;

const supported_os = switch (builtin.os) {
    builtin.os.linux => true,
    builtin.os.macosx => true,
    else => @compileError("unsupported os"),
};

const supported_architecture = switch (builtin.arch) {
    builtin.Arch.x86_64 => true,
    builtin.Arch.i386 => true,
    builtin.Arch.aarch64v8 => true,
    else => @compileError("unsupported arch"), // NCCS can change
};

pub const pid_t = c_int;
pub const cc_t = u8;
pub const tcflag_t = c_uint;
pub const speed_t = c_uint;

const NCCS = 32;
pub const Termios = packed struct {
    c_iflag: tcflag_t,
    c_oflag: tcflag_t,
    c_cflag: tcflag_t,
    c_lflag: tcflag_t,
    c_line: cc_t,
    c_cc: [NCCS]cc_t,
    __c_ispeed: speed_t,
    __c_ospeed: speed_t,
};

pub fn cfgetospeed(tio: *const Termios) speed_t {
    return tio.c_cflag & speed_t(CBAUD);
}

pub fn cfgetispeed(tio: *const Termios) speed_t {
    return cfgetospeed(tio);
}

pub fn cfmakeraw(tio: *Termios) void {
    tio.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    tio.c_oflag &= ~tcflag_t(OPOST);
    tio.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    tio.c_cflag &= ~tcflag_t(CSIZE | PARENB);
    tio.c_cflag |= tcflag_t(CS8);
    tio.c_cc[VMIN] = 1;
    tio.c_cc[VTIME] = 0;
}

pub fn cfsetospeed(tio: *Termios, speed: speed_t) !void {
    if (speed & ~speed_t(CBAUD) != 0) {
        return error.UnexpectedBits;
    }
    tio.c_cflag &= ~speed_t(CBAUD);
    tio.c_cflag |= speed;
}

pub fn cfsetispeed(tio: *Termios, speed: speed_t) !void {
    if (speed != 0) return try cfsetospeed(tio, speed);
}

//TODO: weak linkage?
pub const cfsetspeed = cfsetospeed;

pub fn tcdrain(fd: i32) !void {
    const rc = linux.syscall3(linux.SYS_ioctl, @bitCast(usize, isize(fd)), linux.TCSBRK, 1);
    const err = os.posix.getErrno(rc);
    return switch (err) {
        0 => {},
        else => error.TCSBRK_Failed,
    };
}

pub fn tcflow(fd: i32, action: i32) !void {
    const rc = linux.syscall3(linux.SYS_ioctl, @bitCast(usize, isize(fd)), linux.TCXONC, @bitCast(usize, isize(action)));
    const err = os.posix.getErrno(rc);
    return switch (err) {
        0 => {},
        else => error.TCXONC_Failed,
    };
}

pub fn tcflush(fd: i32, queue: i32) !void {
    _ = linux.ioctl(fd, linux.TCFLSH, queue);
}

pub fn tcgetattr(fd: i32, tio: *Termios) !void {
    const tio_usize = @ptrToInt(tio);
    _ = linux.ioctl(fd, linux.TCGETS, tio_usize);
}

pub fn tcgetsid(fd: i32) !pid_t {
    var sid: pid_t = undefined;
    const sid_usize = @ptrToInt(&sid);
    const rc = linux.syscall3(linux.SYS_ioctl, @bitCast(usize, isize(fd)), linux.TIOCGSID, sid_usize);
    const err = os.posix.getErrno(rc);
    return switch (err) {
        0 => sid,
        else => error.TIOCGSID_Failed,
    };
}

pub fn tcsendbreak(fd: i32, dur: i32) !void {
    // ignore dur, implementation defined, use 0 instead
    const rc = linux.syscall3(linux.SYS_ioctl, @bitCast(usize, isize(fd)), linux.TCSBRK, 0);
    const err = os.posix.getErrno(rc);
    return switch (err) {
        0 => {},
        else => error.TCSBRK_Failed,
    };
}

pub fn tcsetattr(fd: i32, act: u32, tio: *const Termios) void {
    const tio_usize = @ptrToInt(tio);
    _ = linux.ioctl(fd, (linux.TCSETS + act), tio_usize);
    return;
}

pub const VINTR = 0;
pub const VQUIT = 1;
pub const VERASE = 2;
pub const VKILL = 3;
pub const VEOF = 4;
pub const VTIME = 5;
pub const VMIN = 6;
pub const VSWTC = 7;
pub const VSTART = 8;
pub const VSTOP = 9;
pub const VSUSP = 10;
pub const VEOL = 11;
pub const VREPRINT = 12;
pub const VDISCARD = 13;
pub const VWERASE = 14;
pub const VLNEXT = 15;
pub const VEOL2 = 16;

pub const IGNBRK = 0o000001;
pub const BRKINT = 0o000002;
pub const IGNPAR = 0o000004;
pub const PARMRK = 0o000010;
pub const INPCK = 0o000020;
pub const ISTRIP = 0o000040;
pub const INLCR = 0o000100;
pub const IGNCR = 0o000200;
pub const ICRNL = 0o000400;
pub const IUCLC = 0o001000;
pub const IXON = 0o002000;
pub const IXANY = 0o004000;
pub const IXOFF = 0o010000;
pub const IMAXBEL = 0o020000;
pub const IUTF8 = 0o040000;

pub const OPOST = 0o000001;
pub const OLCUC = 0o000002;
pub const ONLCR = 0o000004;
pub const OCRNL = 0o000010;
pub const ONOCR = 0o000020;
pub const ONLRET = 0o000040;
pub const OFILL = 0o000100;
pub const OFDEL = 0o000200;
pub const NLDLY = 0o000400;
pub const NL0 = 0o000000;
pub const NL1 = 0o000400;
pub const CRDLY = 0o003000;
pub const CR0 = 0o000000;
pub const CR1 = 0o001000;
pub const CR2 = 0o002000;
pub const CR3 = 0o003000;
pub const TABDLY = 0o014000;
pub const TAB0 = 0o000000;
pub const TAB1 = 0o004000;
pub const TAB2 = 0o010000;
pub const TAB3 = 0o014000;
pub const BSDLY = 0o020000;
pub const BS0 = 0o000000;
pub const BS1 = 0o020000;
pub const FFDLY = 0o100000;
pub const FF0 = 0o000000;
pub const FF1 = 0o100000;

pub const VTDLY = 0o040000;
pub const VT0 = 0o000000;
pub const VT1 = 0o040000;

pub const B0 = 0o000000;
pub const B50 = 0o000001;
pub const B75 = 0o000002;
pub const B110 = 0o000003;
pub const B134 = 0o000004;
pub const B150 = 0o000005;
pub const B200 = 0o000006;
pub const B300 = 0o000007;
pub const B600 = 0o000010;
pub const B1200 = 0o000011;
pub const B1800 = 0o000012;
pub const B2400 = 0o000013;
pub const B4800 = 0o000014;
pub const B9600 = 0o000015;
pub const B19200 = 0o000016;
pub const B38400 = 0o000017;

pub const B57600 = 0o010001;
pub const B115200 = 0o010002;
pub const B230400 = 0o010003;
pub const B460800 = 0o010004;
pub const B500000 = 0o010005;
pub const B576000 = 0o010006;
pub const B921600 = 0o010007;
pub const B1000000 = 0o010010;
pub const B1152000 = 0o010011;
pub const B1500000 = 0o010012;
pub const B2000000 = 0o010013;
pub const B2500000 = 0o010014;
pub const B3000000 = 0o010015;
pub const B3500000 = 0o010016;
pub const B4000000 = 0o010017;

pub const CSIZE = 0o000060;
pub const CS5 = 0o000000;
pub const CS6 = 0o000020;
pub const CS7 = 0o000040;
pub const CS8 = 0o000060;
pub const CSTOPB = 0o000100;
pub const CREAD = 0o000200;
pub const PARENB = 0o000400;
pub const PARODD = 0o001000;
pub const HUPCL = 0o002000;
pub const CLOCAL = 0o004000;

pub const ISIG = 0o000001;
pub const ICANON = 0o000002;
pub const ECHO = 0o000010;
pub const ECHOE = 0o000020;
pub const ECHOK = 0o000040;
pub const ECHONL = 0o000100;
pub const NOFLSH = 0o000200;
pub const TOSTOP = 0o000400;
pub const IEXTEN = 0o100000;

pub const TCOOFF = 0;
pub const TCOON = 1;
pub const TCIOFF = 2;
pub const TCION = 3;

pub const TCIFLUSH = 0;
pub const TCOFLUSH = 1;
pub const TCIOFLUSH = 2;

pub const TCSANOW = 0;
pub const TCSADRAIN = 1;
pub const TCSAFLUSH = 2;

pub const EXTA = 0o000016;
pub const EXTB = 0o000017;
pub const CBAUD = 0o010017;
pub const CBAUDEX = 0o010000;
pub const CIBAUD = 0o02003600000;
pub const CMSPAR = 0o10000000000;
pub const CRTSCTS = 0o20000000000;

pub const XCASE = 0o000004;
pub const ECHOCTL = 0o001000;
pub const ECHOPRT = 0o002000;
pub const ECHOKE = 0o004000;
pub const FLUSHO = 0o010000;
pub const PENDIN = 0o040000;
pub const EXTPROC = 0o200000;

pub const XTABS = 0o014000;
