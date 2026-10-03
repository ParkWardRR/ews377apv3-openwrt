const std = @import("std");

test "SHA256 empty" {
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

test "SHA256 hello" {
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

test "SHA256 incremental matches single-shot" {
    const data = "the quick brown fox jumps over the lazy dog";

    var h1 = std.crypto.hash.sha2.Sha256.init(.{});
    h1.update(data);
    const d1 = h1.finalResult();

    var h2 = std.crypto.hash.sha2.Sha256.init(.{});
    h2.update(data[0..10]);
    h2.update(data[10..]);
    const d2 = h2.finalResult();

    try std.testing.expectEqualSlices(u8, &d1, &d2);
}
