const std = @import("std");
const posix = std.posix;
const main_mod = @import("main.zig");

const BufWriter = main_mod.BufWriter;
const View = main_mod.View;
const TN = main_mod.TN;
const Key = main_mod.Key;
const all_views = main_mod.all_views;

// ---- Helpers ----------------------------------------------------------------

fn makeWriter() BufWriter {
    const fd = std.c.open("/dev/null", .{ .ACCMODE = .WRONLY }, @as(std.c.mode_t, 0));
    return .{ .fd = fd };
}

fn bufContains(w: *const BufWriter, needle: []const u8) bool {
    if (w.pos < needle.len) return false;
    return std.mem.indexOf(u8, w.buf[0..w.pos], needle) != null;
}

fn bufSlice(w: *const BufWriter) []const u8 {
    return w.buf[0..w.pos];
}

// ---- BufWriter: basic operations --------------------------------------------

test "BufWriter initial state has pos zero" {
    const w = makeWriter();
    try std.testing.expectEqual(@as(usize, 0), w.pos);
}

test "BufWriter out writes data and advances pos" {
    var w = makeWriter();
    w.out("hello");
    try std.testing.expectEqual(@as(usize, 5), w.pos);
    try std.testing.expectEqualSlices(u8, "hello", w.buf[0..5]);
}

test "BufWriter multiple out calls accumulate" {
    var w = makeWriter();
    w.out("abc");
    w.out("def");
    try std.testing.expectEqual(@as(usize, 6), w.pos);
    try std.testing.expectEqualSlices(u8, "abcdef", w.buf[0..6]);
}

test "BufWriter out with empty slice is no-op" {
    var w = makeWriter();
    w.out("");
    try std.testing.expectEqual(@as(usize, 0), w.pos);
}

test "BufWriter flush resets pos to zero" {
    var w = makeWriter();
    w.out("data");
    try std.testing.expect(w.pos > 0);
    w.flush();
    try std.testing.expectEqual(@as(usize, 0), w.pos);
}

test "BufWriter flush on empty buffer is safe" {
    var w = makeWriter();
    w.flush();
    try std.testing.expectEqual(@as(usize, 0), w.pos);
}

test "BufWriter double flush is safe" {
    var w = makeWriter();
    w.out("x");
    w.flush();
    w.flush();
    try std.testing.expectEqual(@as(usize, 0), w.pos);
}

test "BufWriter buffer overflow triggers flush" {
    var w = makeWriter();
    // Fill the buffer with exactly 16384 bytes using 4096-byte chunks
    const chunk: *const [4096]u8 = &([1]u8{'X'} ** 4096);
    w.out(chunk);
    w.out(chunk);
    w.out(chunk);
    w.out(chunk);
    // Buffer should be full now: pos == 16384
    try std.testing.expectEqual(@as(usize, 16384), w.pos);
    // Writing one more byte triggers flush, then writes the byte
    w.out("Y");
    try std.testing.expectEqual(@as(usize, 1), w.pos);
    try std.testing.expectEqual(@as(u8, 'Y'), w.buf[0]);
}

// ---- BufWriter: fmt ---------------------------------------------------------

test "BufWriter fmt formats integers" {
    var w = makeWriter();
    w.fmt("{d}", .{42});
    try std.testing.expectEqualSlices(u8, "42", bufSlice(&w));
}

test "BufWriter fmt formats strings" {
    var w = makeWriter();
    w.fmt("{s} {s}", .{ "hello", "world" });
    try std.testing.expectEqualSlices(u8, "hello world", bufSlice(&w));
}

test "BufWriter fmt formats characters" {
    var w = makeWriter();
    w.fmt("{c}", .{'Z'});
    try std.testing.expectEqualSlices(u8, "Z", bufSlice(&w));
}

test "BufWriter fmt gracefully handles internal buffer overflow" {
    var w = makeWriter();
    // The internal tmp buffer in fmt() is 512 bytes.
    // A format that exceeds 512 bytes should be silently dropped.
    const long: []const u8 = &([1]u8{'X'} ** 600);
    w.fmt("{s}", .{long});
    // bufPrint returns error, so nothing is written
    try std.testing.expectEqual(@as(usize, 0), w.pos);
}

// ---- BufWriter: ANSI escape sequences ---------------------------------------

test "BufWriter fgRgb emits correct escape sequence" {
    var w = makeWriter();
    w.fgRgb(.{ 255, 128, 0 });
    try std.testing.expect(bufContains(&w, "\x1b[38;2;255;128;0m"));
}

test "BufWriter fgRgb with zero values" {
    var w = makeWriter();
    w.fgRgb(.{ 0, 0, 0 });
    try std.testing.expect(bufContains(&w, "\x1b[38;2;0;0;0m"));
}

test "BufWriter bgRgb emits correct escape sequence" {
    var w = makeWriter();
    w.bgRgb(.{ 10, 20, 30 });
    try std.testing.expect(bufContains(&w, "\x1b[48;2;10;20;30m"));
}

test "BufWriter bgRgb with max values" {
    var w = makeWriter();
    w.bgRgb(.{ 255, 255, 255 });
    try std.testing.expect(bufContains(&w, "\x1b[48;2;255;255;255m"));
}

test "BufWriter bold emits correct escape" {
    var w = makeWriter();
    w.bold();
    try std.testing.expectEqualSlices(u8, "\x1b[1m", bufSlice(&w));
}

test "BufWriter dim emits correct escape" {
    var w = makeWriter();
    w.dim();
    try std.testing.expectEqualSlices(u8, "\x1b[2m", bufSlice(&w));
}

test "BufWriter italic emits correct escape" {
    var w = makeWriter();
    w.italic();
    try std.testing.expectEqualSlices(u8, "\x1b[3m", bufSlice(&w));
}

test "BufWriter reset emits correct escape" {
    var w = makeWriter();
    w.reset();
    try std.testing.expectEqualSlices(u8, "\x1b[0m", bufSlice(&w));
}

test "BufWriter moveTo emits 1-based coordinates" {
    var w = makeWriter();
    w.moveTo(0, 0);
    try std.testing.expect(bufContains(&w, "\x1b[1;1H"));
}

test "BufWriter moveTo with offset coordinates" {
    var w = makeWriter();
    w.moveTo(9, 4);
    try std.testing.expect(bufContains(&w, "\x1b[10;5H"));
}

test "BufWriter moveTo with large coordinates" {
    var w = makeWriter();
    w.moveTo(999, 999);
    try std.testing.expect(bufContains(&w, "\x1b[1000;1000H"));
}

test "BufWriter clear emits erase and home" {
    var w = makeWriter();
    w.clear();
    try std.testing.expect(bufContains(&w, "\x1b[2J"));
    try std.testing.expect(bufContains(&w, "\x1b[H"));
}

test "BufWriter hideCursor emits correct sequence" {
    var w = makeWriter();
    w.hideCursor();
    try std.testing.expectEqualSlices(u8, "\x1b[?25l", bufSlice(&w));
}

test "BufWriter showCursor emits correct sequence" {
    var w = makeWriter();
    w.showCursor();
    try std.testing.expectEqualSlices(u8, "\x1b[?25h", bufSlice(&w));
}

test "BufWriter altScreen emits correct sequence" {
    var w = makeWriter();
    w.altScreen();
    try std.testing.expectEqualSlices(u8, "\x1b[?1049h", bufSlice(&w));
}

test "BufWriter mainScreen emits correct sequence" {
    var w = makeWriter();
    w.mainScreen();
    try std.testing.expectEqualSlices(u8, "\x1b[?1049l", bufSlice(&w));
}

test "BufWriter chained ANSI calls produce correct sequence" {
    var w = makeWriter();
    w.bold();
    w.fgRgb(TN.blue);
    w.out("text");
    w.reset();
    // Verify bold + color + text + reset all present in order
    const slice = bufSlice(&w);
    try std.testing.expect(std.mem.indexOf(u8, slice, "\x1b[1m") != null);
    try std.testing.expect(std.mem.indexOf(u8, slice, "text") != null);
    try std.testing.expect(std.mem.indexOf(u8, slice, "\x1b[0m") != null);
    // bold comes before text
    const bold_pos = std.mem.indexOf(u8, slice, "\x1b[1m").?;
    const text_pos = std.mem.indexOf(u8, slice, "text").?;
    const reset_pos = std.mem.indexOf(u8, slice, "\x1b[0m").?;
    try std.testing.expect(bold_pos < text_pos);
    try std.testing.expect(text_pos < reset_pos);
}

// ---- Key enum ---------------------------------------------------------------

test "Key enum has all expected variants" {
    const keys = [_]Key{
        .quit, .up, .down, .left, .right,
        .enter, .tab, .n1, .n2, .n3, .n4, .n5,
        .help, .escape, .none,
    };
    try std.testing.expectEqual(@as(usize, 15), keys.len);
}

test "Key enum variants are all distinct" {
    const keys = [_]Key{
        .quit, .up, .down, .left, .right,
        .enter, .tab, .n1, .n2, .n3, .n4, .n5,
        .help, .escape, .none,
    };
    for (keys, 0..) |k1, i| {
        for (keys[i + 1 ..]) |k2| {
            try std.testing.expect(k1 != k2);
        }
    }
}

// ---- View enum: label() -----------------------------------------------------

test "View dashboard label" {
    try std.testing.expectEqualSlices(u8, "Dashboard", View.dashboard.label());
}

test "View install label" {
    try std.testing.expectEqualSlices(u8, "Install Guide", View.install.label());
}

test "View device label" {
    try std.testing.expectEqualSlices(u8, "Device Info", View.device.label());
}

test "View validation label" {
    try std.testing.expectEqualSlices(u8, "Validation", View.validation.label());
}

test "View releases label" {
    try std.testing.expectEqualSlices(u8, "Releases", View.releases.label());
}

// ---- View enum: num() -------------------------------------------------------

test "View dashboard num" {
    try std.testing.expectEqualSlices(u8, "1", View.dashboard.num());
}

test "View install num" {
    try std.testing.expectEqualSlices(u8, "2", View.install.num());
}

test "View device num" {
    try std.testing.expectEqualSlices(u8, "3", View.device.num());
}

test "View validation num" {
    try std.testing.expectEqualSlices(u8, "4", View.validation.num());
}

test "View releases num" {
    try std.testing.expectEqualSlices(u8, "5", View.releases.num());
}

// ---- View navigation --------------------------------------------------------

test "all_views has five entries" {
    try std.testing.expectEqual(@as(usize, 5), all_views.len);
}

test "all_views order matches enum order" {
    try std.testing.expectEqual(View.dashboard, all_views[0]);
    try std.testing.expectEqual(View.install, all_views[1]);
    try std.testing.expectEqual(View.device, all_views[2]);
    try std.testing.expectEqual(View.validation, all_views[3]);
    try std.testing.expectEqual(View.releases, all_views[4]);
}

test "View tab cycling wraps from last to first" {
    var v: View = .releases;
    const idx = @intFromEnum(v);
    v = @enumFromInt((idx + 1) % all_views.len);
    try std.testing.expectEqual(View.dashboard, v);
}

test "View tab cycling advances one view" {
    var v: View = .dashboard;
    const idx = @intFromEnum(v);
    v = @enumFromInt((idx + 1) % all_views.len);
    try std.testing.expectEqual(View.install, v);
}

test "View tab cycling from middle" {
    var v: View = .device;
    const idx = @intFromEnum(v);
    v = @enumFromInt((idx + 1) % all_views.len);
    try std.testing.expectEqual(View.validation, v);
}

test "View tab cycling through all views returns to start" {
    var v: View = .dashboard;
    var i: usize = 0;
    while (i < all_views.len) : (i += 1) {
        const idx = @intFromEnum(v);
        v = @enumFromInt((idx + 1) % all_views.len);
    }
    try std.testing.expectEqual(View.dashboard, v);
}

test "Number keys select correct views" {
    const Expected = struct { key: Key, view: View };
    const expected = [_]Expected{
        .{ .key = .n1, .view = .dashboard },
        .{ .key = .n2, .view = .install },
        .{ .key = .n3, .view = .device },
        .{ .key = .n4, .view = .validation },
        .{ .key = .n5, .view = .releases },
    };
    for (expected) |e| {
        const v: View = switch (e.key) {
            .n1 => .dashboard,
            .n2 => .install,
            .n3 => .device,
            .n4 => .validation,
            .n5 => .releases,
            else => unreachable,
        };
        try std.testing.expectEqual(e.view, v);
    }
}

// ---- Tokyo Night palette ----------------------------------------------------

test "TN palette has 13 named color entries" {
    // Each is a [3]u8 -- inherently valid RGB (0-255 per component).
    // This test verifies all entries exist and are non-zero.
    const colors = [_][3]u8{
        TN.bg_dark,
        TN.bg_float,
        TN.bg_hl,
        TN.fg_dim,
        TN.fg,
        TN.fg_bright,
        TN.blue,
        TN.magenta,
        TN.green,
        TN.red,
        TN.orange,
        TN.cyan,
        TN.yellow,
    };
    try std.testing.expectEqual(@as(usize, 13), colors.len);
    for (colors) |c| {
        const sum: u16 = @as(u16, c[0]) + @as(u16, c[1]) + @as(u16, c[2]);
        try std.testing.expect(sum > 0);
    }
}

test "TN shimmer has four entries" {
    try std.testing.expectEqual(@as(usize, 4), TN.shimmer.len);
}

test "TN shimmer starts and ends with blue" {
    try std.testing.expectEqualSlices(u8, &TN.blue, &TN.shimmer[0]);
    try std.testing.expectEqualSlices(u8, &TN.blue, &TN.shimmer[3]);
}

test "TN shimmer contains cyan at index 1" {
    try std.testing.expectEqualSlices(u8, &TN.cyan, &TN.shimmer[1]);
}

test "TN shimmer contains magenta at index 2" {
    try std.testing.expectEqualSlices(u8, &TN.magenta, &TN.shimmer[2]);
}

test "TN specific color values are correct" {
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x1a, 0x1b, 0x26 }, &TN.bg_dark);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x7a, 0xa2, 0xf7 }, &TN.blue);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xf7, 0x76, 0x8e }, &TN.red);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x9e, 0xce, 0x6a }, &TN.green);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0x9e, 0x64 }, &TN.orange);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xe0, 0xaf, 0x68 }, &TN.yellow);
}

test "TN bg colors are darker than fg colors" {
    // Background luminance should be lower than foreground luminance
    const bg_lum: u16 = @as(u16, TN.bg_dark[0]) + TN.bg_dark[1] + TN.bg_dark[2];
    const fg_lum: u16 = @as(u16, TN.fg[0]) + TN.fg[1] + TN.fg[2];
    try std.testing.expect(bg_lum < fg_lum);
}

// ---- Rendering functions produce output -------------------------------------

test "renderDashboard produces non-empty output" {
    var w = makeWriter();
    main_mod.renderDashboard(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderDashboard output contains SKU Status" {
    var w = makeWriter();
    main_mod.renderDashboard(&w);
    try std.testing.expect(bufContains(&w, "SKU Status"));
}

test "renderDashboard output contains Hardware" {
    var w = makeWriter();
    main_mod.renderDashboard(&w);
    try std.testing.expect(bufContains(&w, "Hardware"));
}

test "renderInstall produces non-empty output" {
    var w = makeWriter();
    main_mod.renderInstall(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderInstall output contains Install Paths" {
    var w = makeWriter();
    main_mod.renderInstall(&w);
    try std.testing.expect(bufContains(&w, "Install Paths"));
}

test "renderInstall output contains Safety" {
    var w = makeWriter();
    main_mod.renderInstall(&w);
    try std.testing.expect(bufContains(&w, "Safety"));
}

test "renderDevice produces non-empty output" {
    var w = makeWriter();
    main_mod.renderDevice(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderDevice output contains Hardware Reference" {
    var w = makeWriter();
    main_mod.renderDevice(&w);
    try std.testing.expect(bufContains(&w, "Hardware Reference"));
}

test "renderValidation produces non-empty output" {
    var w = makeWriter();
    main_mod.renderValidation(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderValidation output contains Validation Checklist" {
    var w = makeWriter();
    main_mod.renderValidation(&w);
    try std.testing.expect(bufContains(&w, "Validation Checklist"));
}

test "renderValidation output contains progress indicator" {
    var w = makeWriter();
    main_mod.renderValidation(&w);
    try std.testing.expect(bufContains(&w, "4/8"));
}

test "renderReleases produces non-empty output" {
    var w = makeWriter();
    main_mod.renderReleases(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderReleases output contains Release Artifacts" {
    var w = makeWriter();
    main_mod.renderReleases(&w);
    try std.testing.expect(bufContains(&w, "Release Artifacts"));
}

test "renderHelp produces non-empty output" {
    var w = makeWriter();
    main_mod.renderHelp(&w);
    try std.testing.expect(w.pos > 0);
}

test "renderHelp output contains Keyboard Shortcuts" {
    var w = makeWriter();
    main_mod.renderHelp(&w);
    try std.testing.expect(bufContains(&w, "Keyboard Shortcuts"));
}

test "renderHelp output contains quit binding" {
    var w = makeWriter();
    main_mod.renderHelp(&w);
    try std.testing.expect(bufContains(&w, "Quit"));
}

// ---- renderBadge ------------------------------------------------------------

test "renderBadge produces output containing the label" {
    var w = makeWriter();
    main_mod.renderBadge(&w, "PROVEN", TN.green);
    try std.testing.expect(w.pos > 0);
    try std.testing.expect(bufContains(&w, "PROVEN"));
}

test "renderBadge with empty label still produces ANSI output" {
    var w = makeWriter();
    main_mod.renderBadge(&w, "", TN.blue);
    // Even with empty label, background color + bold + reset are emitted
    try std.testing.expect(w.pos > 0);
}

test "renderBadge includes ANSI background color escape" {
    var w = makeWriter();
    main_mod.renderBadge(&w, "TEST", TN.red);
    try std.testing.expect(bufContains(&w, "\x1b[48;2;"));
}

test "renderBadge includes bold and reset" {
    var w = makeWriter();
    main_mod.renderBadge(&w, "X", TN.cyan);
    try std.testing.expect(bufContains(&w, "\x1b[1m"));
    try std.testing.expect(bufContains(&w, "\x1b[0m"));
}

// ---- sectionHeader ----------------------------------------------------------

test "sectionHeader produces output containing the title" {
    var w = makeWriter();
    main_mod.sectionHeader(&w, 5, 3, "My Section");
    try std.testing.expect(w.pos > 0);
    try std.testing.expect(bufContains(&w, "My Section"));
}

test "sectionHeader includes moveTo sequence" {
    var w = makeWriter();
    main_mod.sectionHeader(&w, 0, 0, "Title");
    // moveTo(0, 0) emits \x1b[1;1H (1-based)
    try std.testing.expect(bufContains(&w, "\x1b[1;1H"));
}

test "sectionHeader uses blue foreground color" {
    var w = makeWriter();
    main_mod.sectionHeader(&w, 0, 0, "Title");
    // TN.blue = { 0x7a, 0xa2, 0xf7 } = { 122, 162, 247 }
    try std.testing.expect(bufContains(&w, "\x1b[38;2;122;162;247m"));
}

test "sectionHeader includes bold" {
    var w = makeWriter();
    main_mod.sectionHeader(&w, 0, 0, "Title");
    try std.testing.expect(bufContains(&w, "\x1b[1m"));
}

// ---- Edge cases: terminal size ----------------------------------------------

test "renderStatusBar with zero width does not crash" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .dashboard, 0, 24);
    // No crash = pass
    try std.testing.expect(true);
}

test "renderStatusBar with width 1 does not crash" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .dashboard, 1, 24);
    try std.testing.expect(true);
}

test "renderStatusBar with zero height does not crash" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .dashboard, 80, 0);
    try std.testing.expect(true);
}

test "renderStatusBar with 1x1 terminal does not crash" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .dashboard, 1, 1);
    try std.testing.expect(true);
}

test "renderStatusBar with 0x0 terminal does not crash" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .dashboard, 0, 0);
    try std.testing.expect(true);
}

test "renderTabBar with zero width does not crash" {
    var w = makeWriter();
    main_mod.renderTabBar(&w, .dashboard, 0);
    try std.testing.expect(true);
}

test "renderTabBar with width 1 does not crash" {
    var w = makeWriter();
    main_mod.renderTabBar(&w, .install, 1);
    try std.testing.expect(true);
}

test "renderStatusBar with very narrow width does not crash" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .releases, 5, 10);
    try std.testing.expect(true);
}

// ---- Edge cases: frame counter ----------------------------------------------

test "renderWordmark with very large frame does not crash" {
    var w = makeWriter();
    main_mod.renderWordmark(&w, std.math.maxInt(u32));
    try std.testing.expect(w.pos > 0);
}

test "renderWordmark with frame zero produces output" {
    var w = makeWriter();
    main_mod.renderWordmark(&w, 0);
    try std.testing.expect(w.pos > 0);
}

test "renderWordmark with frame 1 produces output" {
    var w = makeWriter();
    main_mod.renderWordmark(&w, 1);
    try std.testing.expect(w.pos > 0);
}

test "frame counter wrapping arithmetic" {
    var frame: u32 = std.math.maxInt(u32);
    frame +%= 1;
    try std.testing.expectEqual(@as(u32, 0), frame);
}

test "frame counter wrapping at midpoint" {
    var frame: u32 = std.math.maxInt(u32) / 2;
    frame +%= 1;
    try std.testing.expectEqual(@as(u32, std.math.maxInt(u32) / 2 + 1), frame);
}

// ---- renderStatusBar content ------------------------------------------------

test "renderStatusBar includes current view label" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .dashboard, 120, 40);
    try std.testing.expect(bufContains(&w, "Dashboard"));
}

test "renderStatusBar includes EWS377 brand" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .install, 120, 40);
    try std.testing.expect(bufContains(&w, "EWS377"));
}

test "renderStatusBar includes navigation hints" {
    var w = makeWriter();
    main_mod.renderStatusBar(&w, .install, 120, 40);
    try std.testing.expect(bufContains(&w, "view"));
    try std.testing.expect(bufContains(&w, "quit"));
    try std.testing.expect(bufContains(&w, "help"));
}

test "renderStatusBar for each view shows correct label" {
    for (all_views) |v| {
        var w = makeWriter();
        main_mod.renderStatusBar(&w, v, 120, 40);
        try std.testing.expect(bufContains(&w, v.label()));
    }
}

// ---- renderTabBar content ---------------------------------------------------

test "renderTabBar with all views produces output" {
    for (all_views) |v| {
        var w = makeWriter();
        main_mod.renderTabBar(&w, v, 80);
        try std.testing.expect(w.pos > 0);
    }
}

test "renderTabBar output contains view labels" {
    var w = makeWriter();
    main_mod.renderTabBar(&w, .dashboard, 120);
    for (all_views) |v| {
        try std.testing.expect(bufContains(&w, v.label()));
    }
}

test "renderTabBar output contains view numbers" {
    var w = makeWriter();
    main_mod.renderTabBar(&w, .dashboard, 120);
    for (all_views) |v| {
        try std.testing.expect(bufContains(&w, v.num()));
    }
}
