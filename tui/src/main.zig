const std = @import("std");
const posix = std.posix;

const VERSION = "0.4.0";
const REPO = "ParkWardRR/openwrt-engenius-ews377ap-ecw230-ews377fit";
const REPO_URL = "https://github.com/" ++ REPO;

// ─── Colors (ANSI 256) ─────────────────────────────────────────────────────

fn bold(writer: anytype) !void {
    try writer.writeAll("\x1b[1m");
}

fn dim(writer: anytype) !void {
    try writer.writeAll("\x1b[2m");
}

fn reset(writer: anytype) !void {
    try writer.writeAll("\x1b[0m");
}

fn green(writer: anytype) !void {
    try writer.writeAll("\x1b[32m");
}

fn red(writer: anytype) !void {
    try writer.writeAll("\x1b[31m");
}

fn yellow(writer: anytype) !void {
    try writer.writeAll("\x1b[33m");
}

fn cyan(writer: anytype) !void {
    try writer.writeAll("\x1b[36m");
}

fn blue(writer: anytype) !void {
    try writer.writeAll("\x1b[34m");
}

fn magenta(writer: anytype) !void {
    try writer.writeAll("\x1b[35m");
}

// ─── Commands ───────────────────────────────────────────────────────────────

fn cmdInfo(writer: anytype) !void {
    try bold(writer);
    try cyan(writer);
    try writer.writeAll("OpenWrt for EnGenius ap-hk07");
    try reset(writer);
    try dim(writer);
    try writer.print("  v{s}\n\n", .{VERSION});
    try reset(writer);

    try bold(writer);
    try writer.writeAll("Supported models\n");
    try reset(writer);

    const Sku = struct { name: []const u8, pid: []const u8, mgmt: []const u8, status: []const u8 };
    const skus = [_]Sku{
        .{ .name = "EWS377AP v3", .pid = "0x011a", .mgmt = "ezMaster/EWS", .status = "PROVEN" },
        .{ .name = "ECW230v3", .pid = "0x011c", .mgmt = "EnGenius Cloud", .status = "UNTESTED" },
        .{ .name = "EWS377-FIT", .pid = "0x012c", .mgmt = "Standalone/FIT", .status = "UNTESTED" },
    };

    for (skus) |sku| {
        try writer.print("  ", .{});
        try bold(writer);
        try writer.print("{s:<14}", .{sku.name});
        try reset(writer);
        try dim(writer);
        try writer.print("pid {s}  {s:<16}", .{ sku.pid, sku.mgmt });
        try reset(writer);
        if (std.mem.eql(u8, sku.status, "PROVEN")) {
            try green(writer);
        } else {
            try yellow(writer);
        }
        try writer.print(" {s}\n", .{sku.status});
        try reset(writer);
    }

    try writer.writeAll("\n");
    try bold(writer);
    try writer.writeAll("Hardware (shared across all models)\n");
    try reset(writer);

    const specs = [_][2][]const u8{
        .{ "SoC", "Qualcomm IPQ8072A (quad Cortex-A53), ap-hk07" },
        .{ "RAM", "1 GiB (some units 512 MB)" },
        .{ "NAND", "256 MB" },
        .{ "Ethernet", "1x 2.5 GbE (QCA8081 @ MDIO 28)" },
        .{ "Wi-Fi", "4x4 802.11ax dual-band (ath11k)" },
        .{ "LEDs", "RGB status GPIO 54/55/56" },
        .{ "Reset", "GPIO 52 (active-low)" },
        .{ "UART", "Header J2, 115200 8N1" },
        .{ "Boot", "u-boot 2.0.0, bootcmd=bootipq, config@hk07" },
        .{ "Secure boot", "NOT fused" },
        .{ "Sibling", "NETGEAR WAX218 v1 (mainline OpenWrt)" },
    };

    for (specs) |s| {
        try writer.print("  ", .{});
        try cyan(writer);
        try writer.print("{s:<14}", .{s[0]});
        try reset(writer);
        try writer.print("{s}\n", .{s[1]});
    }

    try writer.writeAll("\n");
    try bold(writer);
    try writer.writeAll("Install methods\n");
    try reset(writer);

    const methods = [_]struct { name: []const u8, status: []const u8, proven: bool }{
        .{ .name = "UART + u-boot nand write", .status = "PROVEN", .proven = true },
        .{ .name = "SSH + ubiformat (no cable)", .status = "DOCUMENTED", .proven = false },
        .{ .name = "Web UI upload (one-click)", .status = "EXPERIMENTAL", .proven = false },
        .{ .name = "Initramfs RAM boot", .status = "PROVEN", .proven = true },
    };

    for (methods) |m| {
        try writer.print("  {s:<30}", .{m.name});
        if (m.proven) {
            try green(writer);
        } else {
            try yellow(writer);
        }
        try writer.print(" {s}\n", .{m.status});
        try reset(writer);
    }

    try writer.writeAll("\n");
    try bold(writer);
    try writer.writeAll("Links\n");
    try reset(writer);
    try dim(writer);
    try writer.print("  Repo       {s}\n", .{REPO_URL});
    try writer.print("  Releases   {s}/releases\n", .{REPO_URL});
    try writer.print("  Install    {s}/blob/main/docs/install-and-restore.md\n", .{REPO_URL});
    try writer.print("  Pelegrun   https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools\n", .{});
    try reset(writer);
}

fn cmdVerify(writer: anytype, args: []const [:0]const u8) !void {
    if (args.len == 0) {
        try red(writer);
        try writer.writeAll("Usage: ews377-tool verify <firmware-file> [<sha256-expected>]\n");
        try reset(writer);
        try writer.writeAll("\nComputes SHA256 of the given file. If an expected hash is provided,\n");
        try writer.writeAll("compares against it. Use with SHA256SUMS from the release.\n\n");
        try dim(writer);
        try writer.writeAll("Example:\n");
        try writer.writeAll("  ews377-tool verify openwrt-...-factory.ubi abc123...\n");
        try writer.writeAll("  shasum -a 256 openwrt-...-factory.ubi | ews377-tool verify --stdin\n");
        try reset(writer);
        return;
    }

    const file_path = args[0];
    const expected_hash: ?[]const u8 = if (args.len > 1) args[1] else null;

    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        try red(writer);
        try writer.print("Error: cannot open '{s}': {s}\n", .{ file_path, @errorName(err) });
        try reset(writer);
        return;
    };
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [65536]u8 = undefined;
    var total: u64 = 0;

    while (true) {
        const n = file.read(&buf) catch |err| {
            try red(writer);
            try writer.print("Error reading file: {s}\n", .{@errorName(err)});
            try reset(writer);
            return;
        };
        if (n == 0) break;
        hasher.update(buf[0..n]);
        total += n;
    }

    const digest = hasher.finalResult();
    var hex: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        const high = byte >> 4;
        const low = byte & 0x0f;
        hex[i * 2] = if (high < 10) '0' + high else 'a' + high - 10;
        hex[i * 2 + 1] = if (low < 10) '0' + low else 'a' + low - 10;
    }

    const hash_str = hex[0..64];

    if (expected_hash) |expected| {
        const trimmed = std.mem.trim(u8, expected, " \t\r\n");
        if (trimmed.len >= 64 and std.mem.eql(u8, hash_str, trimmed[0..64])) {
            try green(writer);
            try bold(writer);
            try writer.writeAll("MATCH");
            try reset(writer);
            try writer.print("  {s}  ({d} bytes)\n", .{ hash_str, total });
        } else {
            try red(writer);
            try bold(writer);
            try writer.writeAll("MISMATCH");
            try reset(writer);
            try writer.print("\n  got:      {s}\n  expected: {s}\n  ({d} bytes)\n", .{ hash_str, trimmed, total });
        }
    } else {
        try writer.print("{s}  {s}  ({d} bytes)\n", .{ hash_str, file_path, total });
    }
}

fn cmdProbe(writer: anytype, args: []const [:0]const u8) !void {
    if (args.len == 0) {
        try red(writer);
        try writer.writeAll("Usage: ews377-tool probe <host> [--port 8822] [--user root] [--pass admin]\n");
        try reset(writer);
        try writer.writeAll("\nConnects to an EnGenius AP via SSH and identifies model, firmware,\n");
        try writer.writeAll("partition layout, and boot state. Stock firmware uses port 8822.\n\n");
        try dim(writer);
        try writer.writeAll("Examples:\n");
        try writer.writeAll("  ews377-tool probe 192.168.1.100\n");
        try writer.writeAll("  ews377-tool probe 192.168.1.100 --port 22    # OpenWrt uses standard port\n");
        try reset(writer);
        return;
    }

    const host = args[0];
    var port: []const u8 = "8822";
    var user: []const u8 = "root";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--port") and i + 1 < args.len) {
            i += 1;
            port = args[i];
        } else if (std.mem.eql(u8, arg, "--user") and i + 1 < args.len) {
            i += 1;
            user = args[i];
        }
    }

    try bold(writer);
    try writer.print("Probing {s}@{s}:{s} ...\n\n", .{ user, host, port });
    try reset(writer);

    const ssh_commands = [_]struct { label: []const u8, cmd: []const u8 }{
        .{ .label = "Board identity", .cmd = "cat /tmp/sysinfo/board_name 2>/dev/null || ubus call system board 2>/dev/null | head -6 || echo 'unknown'" },
        .{ .label = "Firmware", .cmd = "cat /etc/openwrt_release 2>/dev/null || cat /etc/os-release 2>/dev/null | head -4 || echo 'stock/unknown'" },
        .{ .label = "Kernel", .cmd = "uname -r 2>/dev/null || echo 'unknown'" },
        .{ .label = "Uptime", .cmd = "uptime 2>/dev/null || echo 'unknown'" },
        .{ .label = "MTD layout", .cmd = "cat /proc/mtd 2>/dev/null | head -20 || echo 'unavailable'" },
        .{ .label = "MAC address", .cmd = "ip link show lan 2>/dev/null | grep ether || ip link show eth0 2>/dev/null | grep ether || echo 'unknown'" },
        .{ .label = "WiFi radios", .cmd = "iw dev 2>/dev/null | grep -E 'Interface|type|channel' || echo 'unavailable'" },
    };

    for (ssh_commands) |entry| {
        try cyan(writer);
        try bold(writer);
        try writer.print("{s}\n", .{entry.label});
        try reset(writer);

        var argv = [_][]const u8{
            "ssh",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "HostKeyAlgorithms=+ssh-rsa",
            "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
            "-o", "BatchMode=yes",
            "-p", port,
            undefined, // user@host placeholder
            entry.cmd,
        };

        var user_host_buf: [256]u8 = undefined;
        const user_host = std.fmt.bufPrint(&user_host_buf, "{s}@{s}", .{ user, host }) catch "root@unknown";
        argv[argv.len - 2] = user_host;

        var child = std.process.Child.init(&argv, std.heap.page_allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        child.spawn() catch |err| {
            try red(writer);
            try writer.print("  SSH failed: {s}\n", .{@errorName(err)});
            try reset(writer);
            try writer.writeAll("  Is SSH accessible? Stock firmware uses port 8822.\n");
            try writer.writeAll("  Managed units may have SSH disabled.\n\n");
            return;
        };

        const result = child.wait() catch |err| {
            try red(writer);
            try writer.print("  Wait failed: {s}\n", .{@errorName(err)});
            try reset(writer);
            continue;
        };

        if (child.stdout) |stdout_pipe| {
            var stdout_buf: [4096]u8 = undefined;
            const stdout_n = stdout_pipe.read(&stdout_buf) catch 0;
            if (stdout_n > 0) {
                try dim(writer);
                const output = std.mem.trim(u8, stdout_buf[0..stdout_n], " \t\r\n");
                for (output) |ch| {
                    try writer.print("{c}", .{ch});
                    if (ch == '\n') try writer.writeAll("  ");
                }
                try writer.writeAll("\n");
                try reset(writer);
            }
        }

        _ = result;
        try writer.writeAll("\n");
    }
}

fn cmdHelp(writer: anytype) !void {
    try bold(writer);
    try cyan(writer);
    try writer.writeAll("ews377-tool");
    try reset(writer);
    try writer.print("  v{s}\n", .{VERSION});
    try writer.writeAll("CLI utility for OpenWrt on EnGenius EWS377AP v3 / ECW230v3 / EWS377-FIT\n\n");

    try bold(writer);
    try writer.writeAll("Commands:\n");
    try reset(writer);

    const cmds = [_][2][]const u8{
        .{ "info", "Print hardware reference, supported models, install methods" },
        .{ "verify <file> [hash]", "SHA256-verify a firmware file" },
        .{ "probe <host>", "SSH to device and identify model/firmware/partitions" },
        .{ "help", "Show this help" },
    };

    for (cmds) |c| {
        try writer.print("  ", .{});
        try green(writer);
        try writer.print("{s:<24}", .{c[0]});
        try reset(writer);
        try writer.print("{s}\n", .{c[1]});
    }

    try writer.writeAll("\n");
    try dim(writer);
    try writer.print("{s}\n", .{REPO_URL});
    try reset(writer);
}

// ─── Entry point ────────────────────────────────────────────────────────────

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    if (args.len < 2) {
        try cmdHelp(stdout);
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "info")) {
        try cmdInfo(stdout);
    } else if (std.mem.eql(u8, cmd, "verify")) {
        try cmdVerify(stdout, args[2..]);
    } else if (std.mem.eql(u8, cmd, "probe")) {
        try cmdProbe(stdout, args[2..]);
    } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try cmdHelp(stdout);
    } else {
        try red(stdout);
        try stdout.print("Unknown command: {s}\n\n", .{cmd});
        try reset(stdout);
        try cmdHelp(stdout);
    }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "SHA256 of empty input" {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    const digest = hasher.finalResult();
    var hex: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        const high = byte >> 4;
        const low = byte & 0x0f;
        hex[i * 2] = if (high < 10) '0' + high else 'a' + high - 10;
        hex[i * 2 + 1] = if (low < 10) '0' + low else 'a' + low - 10;
    }
    try std.testing.expectEqualStrings(
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        &hex,
    );
}

test "SHA256 of known string" {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("hello");
    const digest = hasher.finalResult();
    var hex: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        const high = byte >> 4;
        const low = byte & 0x0f;
        hex[i * 2] = if (high < 10) '0' + high else 'a' + high - 10;
        hex[i * 2 + 1] = if (low < 10) '0' + low else 'a' + low - 10;
    }
    try std.testing.expectEqualStrings(
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        &hex,
    );
}
