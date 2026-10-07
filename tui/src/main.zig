const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

// ─── Tokyo Night palette ─────────────────────────────────────────────────────

pub const TN = struct {
    pub const bg_dark: [3]u8 = .{ 0x1a, 0x1b, 0x26 };
    pub const bg_float: [3]u8 = .{ 0x24, 0x28, 0x3b };
    pub const bg_hl: [3]u8 = .{ 0x29, 0x2e, 0x42 };
    pub const fg_dim: [3]u8 = .{ 0x56, 0x5f, 0x89 };
    pub const fg: [3]u8 = .{ 0xa9, 0xb1, 0xd6 };
    pub const fg_bright: [3]u8 = .{ 0xc0, 0xca, 0xf5 };
    pub const blue: [3]u8 = .{ 0x7a, 0xa2, 0xf7 };
    pub const magenta: [3]u8 = .{ 0xbb, 0x9a, 0xf7 };
    pub const green: [3]u8 = .{ 0x9e, 0xce, 0x6a };
    pub const red: [3]u8 = .{ 0xf7, 0x76, 0x8e };
    pub const orange: [3]u8 = .{ 0xff, 0x9e, 0x64 };
    pub const cyan: [3]u8 = .{ 0x7d, 0xcf, 0xff };
    pub const yellow: [3]u8 = .{ 0xe0, 0xaf, 0x68 };

    pub const shimmer = [_][3]u8{ blue, cyan, magenta, blue };
};

// ─── Buffered terminal output ────────────────────────────────────────────────

pub const BufWriter = struct {
    buf: [16384]u8 = undefined,
    pos: usize = 0,
    fd: posix.fd_t,

    pub fn out(self: *BufWriter, data: []const u8) void {
        for (data) |b| {
            if (self.pos >= self.buf.len) self.flush();
            self.buf[self.pos] = b;
            self.pos += 1;
        }
    }

    pub fn flush(self: *BufWriter) void {
        if (self.pos == 0) return;
        _ = std.c.write(self.fd, self.buf[0..self.pos].ptr, self.pos);
        self.pos = 0;
    }

    pub fn fmt(self: *BufWriter, comptime f: []const u8, args: anytype) void {
        var tmp: [512]u8 = undefined;
        const slice = std.fmt.bufPrint(&tmp, f, args) catch return;
        self.out(slice);
    }

    pub fn fgRgb(self: *BufWriter, c: [3]u8) void {
        self.fmt("\x1b[38;2;{d};{d};{d}m", .{ c[0], c[1], c[2] });
    }

    pub fn bgRgb(self: *BufWriter, c: [3]u8) void {
        self.fmt("\x1b[48;2;{d};{d};{d}m", .{ c[0], c[1], c[2] });
    }

    pub fn bold(self: *BufWriter) void {
        self.out("\x1b[1m");
    }

    pub fn dim(self: *BufWriter) void {
        self.out("\x1b[2m");
    }

    pub fn italic(self: *BufWriter) void {
        self.out("\x1b[3m");
    }

    pub fn reset(self: *BufWriter) void {
        self.out("\x1b[0m");
    }

    pub fn moveTo(self: *BufWriter, row: u16, col: u16) void {
        self.fmt("\x1b[{d};{d}H", .{ row + 1, col + 1 });
    }

    pub fn clear(self: *BufWriter) void {
        self.out("\x1b[2J\x1b[H");
    }

    pub fn hideCursor(self: *BufWriter) void {
        self.out("\x1b[?25l");
    }

    pub fn showCursor(self: *BufWriter) void {
        self.out("\x1b[?25h");
    }

    pub fn altScreen(self: *BufWriter) void {
        self.out("\x1b[?1049h");
    }

    pub fn mainScreen(self: *BufWriter) void {
        self.out("\x1b[?1049l");
    }
};

// ─── Terminal setup ──────────────────────────────────────────────────────────

fn getTermSize() struct { w: u16, h: u16 } {
    var ws: posix.winsize = .{ .col = 80, .row = 24, .xpixel = 0, .ypixel = 0 };
    if (comptime builtin.os.tag == .macos) {
        const ret = std.c.ioctl(posix.STDOUT_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (ret != 0) return .{ .w = 80, .h = 24 };
    }
    return .{ .w = ws.col, .h = ws.row };
}

fn enableRaw(fd: posix.fd_t) !posix.termios {
    const orig = try posix.tcgetattr(fd);
    var raw = orig;
    raw.lflag = posix.tc_lflag_t{};
    raw.iflag = posix.tc_iflag_t{};
    raw.oflag = posix.tc_oflag_t{ .OPOST = true };
    raw.cc[@intFromEnum(posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(posix.V.TIME)] = 1;
    try posix.tcsetattr(fd, .FLUSH, raw);
    return orig;
}

fn disableRaw(fd: posix.fd_t, orig: posix.termios) void {
    posix.tcsetattr(fd, .FLUSH, orig) catch {};
}

// ─── Input ───────────────────────────────────────────────────────────────────

pub const Key = enum { quit, up, down, left, right, enter, tab, n1, n2, n3, n4, n5, help, escape, none };

fn readKey() Key {
    var buf: [8]u8 = undefined;
    const n = posix.read(posix.STDIN_FILENO, &buf) catch return .none;
    if (n == 0) return .none;
    if (n == 1) {
        return switch (buf[0]) {
            'q' => .quit,
            'j' => .down,
            'k' => .up,
            'h' => .left,
            'l' => .right,
            '\r', '\n' => .enter,
            '\t' => .tab,
            '1' => .n1,
            '2' => .n2,
            '3' => .n3,
            '4' => .n4,
            '5' => .n5,
            '?' => .help,
            0x1b => .escape,
            else => .none,
        };
    }
    if (n >= 3 and buf[0] == 0x1b and buf[1] == '[') {
        return switch (buf[2]) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            else => .none,
        };
    }
    return .none;
}

// ─── Views ───────────────────────────────────────────────────────────────────

pub const View = enum {
    dashboard,
    install,
    device,
    validation,
    releases,

    pub fn label(self: View) []const u8 {
        return switch (self) {
            .dashboard => "Dashboard",
            .install => "Install Guide",
            .device => "Device Info",
            .validation => "Validation",
            .releases => "Releases",
        };
    }

    pub fn num(self: View) []const u8 {
        return switch (self) {
            .dashboard => "1",
            .install => "2",
            .device => "3",
            .validation => "4",
            .releases => "5",
        };
    }
};

pub const all_views = [_]View{ .dashboard, .install, .device, .validation, .releases };

// ─── Rendering ───────────────────────────────────────────────────────────────

pub fn renderWordmark(w: *BufWriter, frame: u32) void {
    const art = [_][]const u8{
        "  ______  _    _  _____ ____  ______ ______          _____  ",
        " |  ____|| |  | |/ ____|___ \\|____  |____  |   /\\   |  __ \\ ",
        " | |__   | |  | | (___   __) |   / /    / /   /  \\  | |__) |",
        " |  __|  | |/\\| |\\___ \\ |__ <   / /    / /   / /\\ \\ |  ___/ ",
        " | |____ |  /\\  |____) |___) | / /    / /   / ____ \\| |     ",
        " |______||_/  \\_|_____/|____/ /_/    /_/   /_/    \\_\\_|     ",
    };

    for (art, 0..) |line, line_idx| {
        w.moveTo(@intCast(line_idx + 1), 2);
        w.bold();
        for (line, 0..) |ch, i| {
            const pos: u32 = (@as(u32, @intCast(i)) +% frame *% 2 +% @as(u32, @intCast(line_idx)) * 3) % 48;
            const pidx = pos / 12;
            w.fgRgb(TN.shimmer[pidx % TN.shimmer.len]);
            w.fmt("{c}", .{ch});
        }
        w.reset();
    }

    w.moveTo(8, 2);
    w.fgRgb(TN.fg_dim);
    w.italic();
    w.out("OpenWrt on EnGenius ap-hk07 \xe2\x80\x94 IPQ8072A Wi-Fi 6 access point");
    w.reset();
}

pub fn renderTabBar(w: *BufWriter, current: View, width: u16) void {
    const row: u16 = 10;

    w.moveTo(row, 0);
    w.fgRgb(TN.bg_hl);
    var i: u16 = 0;
    while (i < width) : (i += 1) w.out("\xe2\x94\x80");

    w.moveTo(row + 1, 2);
    for (all_views) |v| {
        if (v == current) {
            w.fgRgb(TN.bg_dark);
            w.bgRgb(TN.blue);
            w.bold();
        } else {
            w.fgRgb(TN.fg_dim);
            w.bgRgb(TN.bg_dark);
        }
        w.fmt(" {s} {s} ", .{ v.num(), v.label() });
        w.reset();
        w.out("  ");
    }

    w.moveTo(row + 2, 0);
    w.fgRgb(TN.bg_hl);
    i = 0;
    while (i < width) : (i += 1) w.out("\xe2\x94\x80");
    w.reset();
}

pub fn renderBadge(w: *BufWriter, label: []const u8, color: [3]u8) void {
    w.bgRgb(color);
    w.fgRgb(TN.bg_dark);
    w.bold();
    w.fmt(" {s} ", .{label});
    w.reset();
}

pub fn sectionHeader(w: *BufWriter, row: u16, col: u16, title: []const u8) void {
    w.moveTo(row, col);
    w.fgRgb(TN.blue);
    w.bold();
    w.out(title);
    w.reset();
}

pub fn renderDashboard(w: *BufWriter) void {
    const top: u16 = 14;
    const pad: u16 = 3;

    sectionHeader(w, top, pad, "SKU Status");

    const Sku = struct { name: []const u8, pid: []const u8, status: []const u8, color: [3]u8 };
    const skus = [_]Sku{
        .{ .name = "EWS377AP v3", .pid = "0x011a", .status = "PROVEN", .color = TN.green },
        .{ .name = "ECW230v3", .pid = "0x011c", .status = "DTS VALIDATED", .color = TN.yellow },
        .{ .name = "EWS377-FIT", .pid = "0x012c", .status = "DTS VALIDATED", .color = TN.yellow },
    };

    for (skus, 0..) |sku, i| {
        const row = top + 2 + @as(u16, @intCast(i));
        w.moveTo(row, pad + 1);
        w.fgRgb(TN.fg_bright);
        w.bold();
        w.fmt("{s:<14}", .{sku.name});
        w.reset();
        w.fgRgb(TN.fg_dim);
        w.fmt("  pid {s}  ", .{sku.pid});
        renderBadge(w, sku.status, sku.color);
    }

    sectionHeader(w, top + 7, pad, "Install Methods");

    const Method = struct { name: []const u8, status: []const u8, color: [3]u8 };
    const methods = [_]Method{
        .{ .name = "UART + u-boot nand write", .status = "PROVEN", .color = TN.green },
        .{ .name = "SSH + ubiformat", .status = "DOCUMENTED", .color = TN.cyan },
        .{ .name = "Web UI upload (Method B)", .status = "MECHANISM OK", .color = TN.orange },
        .{ .name = "Initramfs RAM boot", .status = "PROVEN", .color = TN.green },
    };

    for (methods, 0..) |m, i| {
        const row = top + 9 + @as(u16, @intCast(i));
        w.moveTo(row, pad + 1);
        w.fgRgb(TN.fg);
        w.fmt("{s:<28}", .{m.name});
        renderBadge(w, m.status, m.color);
    }

    sectionHeader(w, top + 15, pad, "Hardware");

    const facts = [_][2][]const u8{
        .{ "SoC", "IPQ8072A (quad A53), ap-hk07" },
        .{ "RAM", "1 GiB" },
        .{ "NAND", "256 MB" },
        .{ "Ethernet", "2.5 GbE (QCA8081)" },
        .{ "Wi-Fi", "4x4 802.11ax dual-band (ath11k)" },
        .{ "Release", "v0.2" },
    };

    for (facts, 0..) |f, i| {
        const row = top + 17 + @as(u16, @intCast(i));
        w.moveTo(row, pad + 1);
        w.fgRgb(TN.fg_dim);
        w.fmt("{s:<12}", .{f[0]});
        w.fgRgb(TN.fg);
        w.out(f[1]);
    }
    w.reset();
}

pub fn renderInstall(w: *BufWriter) void {
    const top: u16 = 14;
    const pad: u16 = 3;

    sectionHeader(w, top, pad, "Install Paths");

    const Path = struct { letter: []const u8, name: []const u8, desc: []const u8, risk: []const u8, color: [3]u8 };
    const paths = [_]Path{
        .{
            .letter = "A",
            .name = "UART + u-boot (serial cable)",
            .desc = "Proven, safest. Requires USB-to-serial adapter on header J2.",
            .risk = "LOW RISK",
            .color = TN.green,
        },
        .{
            .letter = "B",
            .name = "SSH + ubiformat (no cable)",
            .desc = "Mirrored from WAX218 method. Not yet hardware-tested on EWS377.",
            .risk = "UNTESTED",
            .color = TN.orange,
        },
        .{
            .letter = "C",
            .name = "Web UI upload (per-SKU image)",
            .desc = "Download the .bin matching your SKU (282/284/300). Persistence unconfirmed.",
            .risk = "EXPERIMENTAL",
            .color = TN.red,
        },
    };

    for (paths, 0..) |p, i| {
        const row = top + 2 + @as(u16, @intCast(i)) * 4;
        w.moveTo(row, pad + 1);
        w.bgRgb(p.color);
        w.fgRgb(TN.bg_dark);
        w.bold();
        w.fmt(" {s} ", .{p.letter});
        w.reset();
        w.out("  ");
        w.fgRgb(TN.fg_bright);
        w.bold();
        w.out(p.name);
        w.reset();
        w.moveTo(row + 1, pad + 6);
        w.fgRgb(TN.fg);
        w.out(p.desc);
        w.moveTo(row + 2, pad + 6);
        renderBadge(w, p.risk, p.color);
    }

    const alert_row = top + 16;
    w.moveTo(alert_row, pad);
    w.fgRgb(TN.red);
    w.bold();
    w.out("\xe2\x9a\xa0  Safety");
    w.reset();

    const warnings = [_][]const u8{
        "Back up NAND (MAC + radio cal are unique) before any flash",
        "Never write ART partition or bootloader region (0x0-0x1000000)",
        "Never hardcode an MTD number \xe2\x80\x94 verify live with cat /proc/mtd",
        "Keep UART attached until install method is proven on your unit",
    };

    for (warnings, 0..) |wn, i| {
        w.moveTo(alert_row + 1 + @as(u16, @intCast(i)), pad + 3);
        w.fgRgb(TN.fg_dim);
        w.out("\xe2\x80\xa2 ");
        w.fgRgb(TN.fg);
        w.out(wn);
    }
    w.reset();
}

pub fn renderDevice(w: *BufWriter) void {
    const top: u16 = 14;
    const pad: u16 = 3;

    sectionHeader(w, top, pad, "Hardware Reference \xe2\x80\x94 EWS377AP v3");

    const specs = [_][2][]const u8{
        .{ "SoC", "Qualcomm IPQ8072A (quad Cortex-A53 @ 2.2 GHz)" },
        .{ "Board", "ap-hk07 reference design" },
        .{ "RAM", "1 GiB DDR3 (confirmed live; some variants 512 MB)" },
        .{ "NAND", "256 MB SPI-NAND" },
        .{ "Ethernet", "1x 2.5 GbE LAN (QCA8081 @ MDIO 28, 2500base-x)" },
        .{ "Wi-Fi 2.4G", "4x4 802.11ax (ath11k, board_id=0x290)" },
        .{ "Wi-Fi 5G", "4x4 802.11ax (ath11k, board_id=0x290)" },
        .{ "LEDs", "RGB status on GPIO 54 / 55 / 56" },
        .{ "Reset", "GPIO 52" },
        .{ "UART", "Header J2, 115200 8N1" },
        .{ "Boot", "QCA u-boot 2.0.0, bootcmd=bootipq, dual A/B" },
        .{ "Secure boot", "NOT fused (custom images boot)" },
    };

    for (specs, 0..) |s, i| {
        const row = top + 2 + @as(u16, @intCast(i));
        w.moveTo(row, pad + 1);
        w.fgRgb(TN.cyan);
        w.fmt("{s:<14}", .{s[0]});
        w.fgRgb(TN.fg);
        w.out(s[1]);
    }

    sectionHeader(w, top + 16, pad, "Siblings (same ap-hk07 silicon)");

    const siblings = [_][2][]const u8{
        .{ "NETGEAR WAX218 v1", "Officially supported in OpenWrt mainline" },
        .{ "EnGenius ECW230v3", "DTS validated identical" },
        .{ "EnGenius EWS377-FIT", "DTS validated identical" },
    };

    for (siblings, 0..) |s, i| {
        const row = top + 18 + @as(u16, @intCast(i));
        w.moveTo(row, pad + 1);
        w.fgRgb(TN.fg_bright);
        w.bold();
        w.fmt("{s:<22}", .{s[0]});
        w.reset();
        w.fgRgb(TN.fg_dim);
        w.out(s[1]);
    }
    w.reset();
}

pub fn renderValidation(w: *BufWriter) void {
    const top: u16 = 14;
    const pad: u16 = 3;

    sectionHeader(w, top, pad, "Validation Checklist");

    const Item = struct { done: bool, text: []const u8 };
    const items = [_]Item{
        .{ .done = true, .text = "DTS identical across all 3 SKUs (reset, LEDs, WiFi, PHY)" },
        .{ .done = true, .text = "WiFi board-id 0x290 confirmed on all 3 SKUs" },
        .{ .done = true, .text = "Per-SKU capwap firmware_ver/datecode conventions extracted" },
        .{ .done = true, .text = "upload.cgi rejection cause identified (product_id mismatch)" },
        .{ .done = true, .text = "Multi-SKU build automation (3 web-ui images per release)" },
        .{ .done = false, .text = "Method B persistence on a second unit (community help wanted)" },
        .{ .done = false, .text = "SSH + ubiformat hardware test on any EnGenius SKU" },
        .{ .done = false, .text = "Live boot/flash state machine capture per SKU" },
        .{ .done = false, .text = "Radio/regulatory provenance per SKU (FCC ID, BDF variant)" },
    };

    for (items, 0..) |item, i| {
        const row = top + 2 + @as(u16, @intCast(i));
        w.moveTo(row, pad + 1);
        if (item.done) {
            w.fgRgb(TN.green);
            w.out("\xe2\x9c\x93 ");
            w.fgRgb(TN.fg);
        } else {
            w.fgRgb(TN.orange);
            w.out("\xe2\x97\x8b ");
            w.fgRgb(TN.fg_dim);
        }
        w.out(item.text);
    }

    const bar_row = top + 13;
    w.moveTo(bar_row, pad);
    w.fgRgb(TN.fg_dim);
    w.out("Progress: 5/9  ");

    const bar_width: u16 = 30;
    const filled: u16 = (bar_width * 5) / 9;
    w.out("[");
    var b: u16 = 0;
    while (b < bar_width) : (b += 1) {
        if (b < filled) {
            w.fgRgb(TN.green);
            w.out("\xe2\x96\x88");
        } else {
            w.fgRgb(TN.bg_hl);
            w.out("\xe2\x96\x91");
        }
    }
    w.fgRgb(TN.fg_dim);
    w.out("]");
    w.reset();
}

pub fn renderReleases(w: *BufWriter) void {
    const top: u16 = 14;
    const pad: u16 = 3;

    sectionHeader(w, top, pad, "Release Artifacts \xe2\x80\x94 v0.2");

    const Artifact = struct { file: []const u8, use: []const u8, persistent: bool, status: []const u8, color: [3]u8 };
    const artifacts = [_]Artifact{
        .{ .file = "squashfs-factory.ubi", .use = "UART/u-boot nand write, or SSH+ubiformat", .persistent = true, .status = "HW PROVEN", .color = TN.green },
        .{ .file = "initramfs-uImage.itb", .use = "RAM boot (dry-run / recovery)", .persistent = false, .status = "PROVEN", .color = TN.green },
        .{ .file = "squashfs-sysupgrade.bin", .use = "Upgrade from running OpenWrt", .persistent = true, .status = "STANDARD", .color = TN.cyan },
        .{ .file = "web-ui-ews377apv3.bin", .use = "OEM web upload \xe2\x80\x94 EWS377AP v3 (pid 282)", .persistent = false, .status = "EXPERIMENTAL", .color = TN.orange },
        .{ .file = "web-ui-ecw230v3.bin", .use = "OEM web upload \xe2\x80\x94 ECW230v3 cloud (pid 284)", .persistent = false, .status = "EXPERIMENTAL", .color = TN.orange },
        .{ .file = "web-ui-ews377fit.bin", .use = "OEM web upload \xe2\x80\x94 EWS377-FIT (pid 300)", .persistent = false, .status = "EXPERIMENTAL", .color = TN.orange },
    };

    for (artifacts, 0..) |a, i| {
        const row = top + 2 + @as(u16, @intCast(i)) * 2;
        w.moveTo(row, pad + 1);
        w.fgRgb(TN.fg_bright);
        w.bold();
        w.out(a.file);
        w.reset();
        w.out("  ");
        renderBadge(w, a.status, a.color);
        w.out("  ");
        if (a.persistent) {
            w.fgRgb(TN.green);
            w.out("persistent");
        } else {
            w.fgRgb(TN.fg_dim);
            w.out("temporary");
        }
        w.moveTo(row + 1, pad + 3);
        w.fgRgb(TN.fg);
        w.out(a.use);
    }

    const note_row = top + 2 + @as(u16, @intCast(artifacts.len)) * 2 + 1;
    w.moveTo(note_row, pad);
    w.fgRgb(TN.fg_dim);
    w.italic();
    w.out("web-ui images are identical payloads \xe2\x80\x94 only the Senao header product_id differs");
    w.reset();
}

pub fn renderHelp(w: *BufWriter) void {
    const top: u16 = 14;
    const pad: u16 = 3;

    sectionHeader(w, top, pad, "Keyboard Shortcuts");

    const bindings = [_][2][]const u8{
        .{ "1-5", "Switch to view" },
        .{ "Tab", "Next view" },
        .{ "?", "Toggle this help" },
        .{ "q", "Quit" },
    };

    for (bindings, 0..) |b, i| {
        const row = top + 2 + @as(u16, @intCast(i));
        w.moveTo(row, pad + 1);
        w.fgRgb(TN.blue);
        w.bold();
        w.fmt("{s:<8}", .{b[0]});
        w.reset();
        w.fgRgb(TN.fg);
        w.out(b[1]);
    }
    w.reset();
}

pub fn renderStatusBar(w: *BufWriter, current: View, width: u16, height: u16) void {
    const row = height -| 1;
    w.moveTo(row, 0);
    w.bgRgb(TN.bg_float);
    var i: u16 = 0;
    while (i < width) : (i += 1) w.out(" ");

    w.moveTo(row, 2);
    w.fgRgb(TN.fg_dim);
    w.out("1-5");
    w.fgRgb(TN.fg);
    w.out(" view  ");
    w.fgRgb(TN.fg_dim);
    w.out("Tab");
    w.fgRgb(TN.fg);
    w.out(" next  ");
    w.fgRgb(TN.fg_dim);
    w.out("?");
    w.fgRgb(TN.fg);
    w.out(" help  ");
    w.fgRgb(TN.fg_dim);
    w.out("q");
    w.fgRgb(TN.fg);
    w.out(" quit");

    const crumb = current.label();
    const right_col = width -| @as(u16, @intCast(crumb.len + 16));
    w.moveTo(row, right_col);
    w.fgRgb(TN.blue);
    w.bold();
    w.out("EWS377");
    w.reset();
    w.bgRgb(TN.bg_float);
    w.fgRgb(TN.fg_dim);
    w.out(" > ");
    w.fgRgb(TN.fg);
    w.out(crumb);
    w.reset();
}

// ─── Main loop ───────────────────────────────────────────────────────────────

// ─── Tests ───────────────────────────────────────────────────────────────────

fn testWriter() BufWriter {
    const fd = std.c.open("/dev/null", .{ .ACCMODE = .WRONLY }, @as(std.c.mode_t, 0));
    return BufWriter{ .fd = fd };
}

test "BufWriter: out fills buffer" {
    var w = testWriter();
    w.out("hello");
    try std.testing.expectEqual(@as(usize, 5), w.pos);
}

test "BufWriter: flush resets pos" {
    var w = testWriter();
    w.out("data");
    try std.testing.expect(w.pos > 0);
    w.flush();
    try std.testing.expectEqual(@as(usize, 0), w.pos);
}

test "BufWriter: fmt formats correctly" {
    var w = testWriter();
    w.fmt("{d}+{d}={d}", .{ 1, 2, 3 });
    try std.testing.expectEqual(@as(usize, 5), w.pos);
    try std.testing.expectEqualStrings("1+2=3", w.buf[0..5]);
}

test "BufWriter: fgRgb emits ANSI escape" {
    var w = testWriter();
    w.fgRgb(.{ 0x7a, 0xa2, 0xf7 });
    const expected = "\x1b[38;2;122;162;247m";
    try std.testing.expectEqualStrings(expected, w.buf[0..w.pos]);
}

test "BufWriter: bgRgb emits ANSI escape" {
    var w = testWriter();
    w.bgRgb(.{ 0x1a, 0x1b, 0x26 });
    const expected = "\x1b[48;2;26;27;38m";
    try std.testing.expectEqualStrings(expected, w.buf[0..w.pos]);
}

test "BufWriter: bold emits correct sequence" {
    var w = testWriter();
    w.bold();
    try std.testing.expectEqualStrings("\x1b[1m", w.buf[0..w.pos]);
}

test "BufWriter: dim emits correct sequence" {
    var w = testWriter();
    w.dim();
    try std.testing.expectEqualStrings("\x1b[2m", w.buf[0..w.pos]);
}

test "BufWriter: italic emits correct sequence" {
    var w = testWriter();
    w.italic();
    try std.testing.expectEqualStrings("\x1b[3m", w.buf[0..w.pos]);
}

test "BufWriter: reset emits correct sequence" {
    var w = testWriter();
    w.reset();
    try std.testing.expectEqualStrings("\x1b[0m", w.buf[0..w.pos]);
}

test "BufWriter: moveTo emits cursor position" {
    var w = testWriter();
    w.moveTo(5, 10);
    try std.testing.expectEqualStrings("\x1b[6;11H", w.buf[0..w.pos]);
}

test "BufWriter: clear emits erase + home" {
    var w = testWriter();
    w.clear();
    try std.testing.expectEqualStrings("\x1b[2J\x1b[H", w.buf[0..w.pos]);
}

test "BufWriter: hideCursor emits correct sequence" {
    var w = testWriter();
    w.hideCursor();
    try std.testing.expectEqualStrings("\x1b[?25l", w.buf[0..w.pos]);
}

test "BufWriter: showCursor emits correct sequence" {
    var w = testWriter();
    w.showCursor();
    try std.testing.expectEqualStrings("\x1b[?25h", w.buf[0..w.pos]);
}

test "BufWriter: altScreen emits correct sequence" {
    var w = testWriter();
    w.altScreen();
    try std.testing.expectEqualStrings("\x1b[?1049h", w.buf[0..w.pos]);
}

test "BufWriter: mainScreen emits correct sequence" {
    var w = testWriter();
    w.mainScreen();
    try std.testing.expectEqualStrings("\x1b[?1049l", w.buf[0..w.pos]);
}

test "BufWriter: buffer overflow flushes automatically" {
    var w = testWriter();
    const chunk = "x" ** 100;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        w.out(chunk);
    }
    try std.testing.expect(w.pos < w.buf.len);
}

test "View: label returns correct strings" {
    try std.testing.expectEqualStrings("Dashboard", View.dashboard.label());
    try std.testing.expectEqualStrings("Install Guide", View.install.label());
    try std.testing.expectEqualStrings("Device Info", View.device.label());
    try std.testing.expectEqualStrings("Validation", View.validation.label());
    try std.testing.expectEqualStrings("Releases", View.releases.label());
}

test "View: num returns correct shortcut keys" {
    try std.testing.expectEqualStrings("1", View.dashboard.num());
    try std.testing.expectEqualStrings("2", View.install.num());
    try std.testing.expectEqualStrings("3", View.device.num());
    try std.testing.expectEqualStrings("4", View.validation.num());
    try std.testing.expectEqualStrings("5", View.releases.num());
}

test "View: all_views has 5 entries" {
    try std.testing.expectEqual(@as(usize, 5), all_views.len);
}

test "View: tab cycling wraps around" {
    var current: View = .releases;
    const idx = @intFromEnum(current);
    current = @enumFromInt((idx + 1) % all_views.len);
    try std.testing.expectEqual(View.dashboard, current);
}

test "View: tab cycling from dashboard" {
    var current: View = .dashboard;
    const idx = @intFromEnum(current);
    current = @enumFromInt((idx + 1) % all_views.len);
    try std.testing.expectEqual(View.install, current);
}

test "Tokyo Night: palette values are valid" {
    inline for (.{ TN.bg_dark, TN.bg_float, TN.bg_hl, TN.fg_dim, TN.fg, TN.fg_bright, TN.blue, TN.magenta, TN.green, TN.red, TN.orange, TN.cyan, TN.yellow }) |color| {
        try std.testing.expect(color[0] <= 255);
        try std.testing.expect(color[1] <= 255);
        try std.testing.expect(color[2] <= 255);
    }
}

test "Tokyo Night: shimmer palette has 4 entries" {
    try std.testing.expectEqual(@as(usize, 4), TN.shimmer.len);
}

test "renderDashboard: produces non-empty output" {
    var w = testWriter();
    renderDashboard(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderInstall: produces non-empty output" {
    var w = testWriter();
    renderInstall(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderDevice: produces non-empty output" {
    var w = testWriter();
    renderDevice(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderValidation: produces non-empty output" {
    var w = testWriter();
    renderValidation(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderReleases: produces non-empty output" {
    var w = testWriter();
    renderReleases(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderHelp: produces non-empty output" {
    var w = testWriter();
    renderHelp(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderWordmark: produces output with shimmer" {
    var w = testWriter();
    renderWordmark(&w, 0);
    try std.testing.expect(w.pos > 100);
}

test "renderWordmark: different frames produce different output" {
    var w1 = testWriter();
    renderWordmark(&w1, 0);
    const pos1 = w1.pos;
    const snapshot1 = w1.buf[0..pos1];

    var w2 = testWriter();
    renderWordmark(&w2, 5);
    const pos2 = w2.pos;
    const snapshot2 = w2.buf[0..pos2];

    var differs = false;
    if (pos1 != pos2) {
        differs = true;
    } else {
        for (snapshot1, snapshot2) |a, b| {
            if (a != b) {
                differs = true;
                break;
            }
        }
    }
    try std.testing.expect(differs);
}

test "renderBadge: output contains label text" {
    var w = testWriter();
    renderBadge(&w, "PROVEN", TN.green);
    const output = w.buf[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "PROVEN") != null);
}

test "sectionHeader: output contains title text" {
    var w = testWriter();
    sectionHeader(&w, 0, 0, "Test Header");
    const output = w.buf[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "Test Header") != null);
}

test "renderTabBar: produces non-empty output" {
    var w = testWriter();
    renderTabBar(&w, .dashboard, 80);
    try std.testing.expect(w.pos > 0);
}

test "renderStatusBar: produces non-empty output" {
    var w = testWriter();
    renderStatusBar(&w, .dashboard, 80, 24);
    try std.testing.expect(w.pos > 0);
}

test "renderStatusBar: handles narrow width" {
    var w = testWriter();
    renderStatusBar(&w, .dashboard, 10, 5);
    try std.testing.expect(w.pos > 0);
}

test "renderStatusBar: handles zero dimensions" {
    var w = testWriter();
    renderStatusBar(&w, .dashboard, 0, 0);
    try std.testing.expect(w.pos > 0);
}

test "renderTabBar: handles very narrow width" {
    var w = testWriter();
    renderTabBar(&w, .validation, 1);
    try std.testing.expect(w.pos > 0);
}

test "renderWordmark: handles max frame counter" {
    var w = testWriter();
    renderWordmark(&w, std.math.maxInt(u32));
    try std.testing.expect(w.pos > 0);
}

test "getTermSize: returns non-panic values" {
    const sz = getTermSize();
    _ = sz.w;
    _ = sz.h;
}

test "Key enum: all variants exist" {
    const keys = [_]Key{ .quit, .up, .down, .left, .right, .enter, .tab, .n1, .n2, .n3, .n4, .n5, .help, .escape, .none };
    try std.testing.expectEqual(@as(usize, 15), keys.len);
}

test "BufWriter: sequential operations compose correctly" {
    var w = testWriter();
    w.bold();
    w.fgRgb(TN.blue);
    w.out("test");
    w.reset();
    const output = w.buf[0..w.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[1m") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[0m") != null);
}

// ─── Entry point ─────────────────────────────────────────────────────────────

pub fn main() !void {
    const fd = posix.STDIN_FILENO;
    const orig = try enableRaw(fd);
    defer disableRaw(fd, orig);

    var w = BufWriter{ .fd = posix.STDOUT_FILENO };
    w.altScreen();
    w.hideCursor();
    defer {
        w.showCursor();
        w.mainScreen();
        w.flush();
    }

    var current_view: View = .dashboard;
    var frame: u32 = 0;
    var show_help = false;
    var running = true;

    while (running) {
        const sz = getTermSize();
        w.clear();
        w.bgRgb(TN.bg_dark);

        renderWordmark(&w, frame);
        renderTabBar(&w, current_view, sz.w);

        if (show_help) {
            renderHelp(&w);
        } else {
            switch (current_view) {
                .dashboard => renderDashboard(&w),
                .install => renderInstall(&w),
                .device => renderDevice(&w),
                .validation => renderValidation(&w),
                .releases => renderReleases(&w),
            }
        }

        renderStatusBar(&w, current_view, sz.w, sz.h);
        w.flush();

        frame +%= 1;

        const key = readKey();
        if (show_help and key != .none) {
            show_help = false;
            continue;
        }
        switch (key) {
            .quit => running = false,
            .n1 => {
                current_view = .dashboard;
            },
            .n2 => {
                current_view = .install;
            },
            .n3 => {
                current_view = .device;
            },
            .n4 => {
                current_view = .validation;
            },
            .n5 => {
                current_view = .releases;
            },
            .help => show_help = true,
            .tab => {
                const idx = @intFromEnum(current_view);
                current_view = @enumFromInt((idx + 1) % all_views.len);
            },
            else => {},
        }
    }
}
