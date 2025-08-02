const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");

test "encode-and-decode-vector-of-strings" {
    const allocator = std.testing.allocator;

    var strings = [_][]const u8{ "Hello", "World" };

    const test_cases = [_]struct {
        value: [][]const u8,
        encoded: []const u8,
    }{
        .{
            .value = strings[0..],
            .encoded = &[_]u8{
                0x08, // Compact length (2)
                0x14, // Compact length (5) for "Hello"
                0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
                0x14, // Compact length (5) for "World"
                0x57, 0x6f, 0x72, 0x6c, 0x64, // "World"
            },
        },
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc([][]const u8, allocator, tc.encoded);
        defer allocator.free(result.value);
        defer for (result.value) |str| allocator.free(str);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqual(result.value.len, tc.value.len);
        for (result.value, tc.value) |decoded_str, expected_str| {
            try std.testing.expectEqualStrings(expected_str, decoded_str);
        }
    }
}

test "encode-and-decode-vector-of-u32" {
    const allocator = std.testing.allocator;

    const test_cases = [_]struct {
        value: []const u32,
        encoded: []const u8,
    }{
        .{ .value = &[_]u32{ 1, 2, 3 }, .encoded = &[_]u8{ 0x0c, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00 } },
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc([]u32, allocator, tc.encoded);
        defer allocator.free(result.value);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqualSlices(u32, tc.value, result.value);
    }
}

test "encode-and-decode-tuple" {
    const allocator = std.testing.allocator;

    const tuple: struct { u32, bool } = .{ 100, false };
    const encoded = &[_]u8{ 0x64, 0x00, 0x00, 0x00, 0x00 };

    // Test encoding
    const buffer = try encoder.encodeAlloc(allocator, tuple);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, encoded, buffer);

    // Test decoding
    const result = try decoder.decodeAlloc(struct { u32, bool }, allocator, encoded);
    try std.testing.expectEqual(result.bytes_read, encoded.len);
    try std.testing.expectEqual(result.value, tuple);
}

test "encode-and-decode-unsigned-integer" {
    const allocator = std.testing.allocator;

    const Value = union(enum) {
        u8: u8,
        u16: u16,
        u32: u32,
        u64: u64,
        u128: u128,
    };

    const test_cases = [_]struct {
        value: Value,
        encoded: []const u8,
    }{
        .{ .value = .{ .u8 = 42 }, .encoded = &[_]u8{0x2a} },
        .{ .value = .{ .u16 = 42 }, .encoded = &[_]u8{ 0x2a, 0x00 } },
        .{ .value = .{ .u16 = 10752 }, .encoded = &[_]u8{ 0x00, 0x2a } },
        .{ .value = .{ .u32 = 42 }, .encoded = &[_]u8{ 0x2a, 0x00, 0x00, 0x00 } },
        .{ .value = .{ .u32 = 704643072 }, .encoded = &[_]u8{ 0x00, 0x00, 0x00, 0x2a } },
        .{ .value = .{ .u64 = 42 }, .encoded = &[_]u8{ 0x2a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .value = .{ .u64 = 3026418949592973312 }, .encoded = &[_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2a } },
        .{ .value = .{ .u128 = 42 }, .encoded = &[_]u8{ 0x2a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .value = .{ .u128 = 55827575822966466661959896531774472192 }, .encoded = &[_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2a } },
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = switch (tc.value) {
            .u8 => try encoder.encodeAlloc(allocator, tc.value.u8),
            .u16 => try encoder.encodeAlloc(allocator, tc.value.u16),
            .u32 => try encoder.encodeAlloc(allocator, tc.value.u32),
            .u64 => try encoder.encodeAlloc(allocator, tc.value.u64),
            .u128 => try encoder.encodeAlloc(allocator, tc.value.u128),
        };
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        switch (tc.value) {
            .u8 => {
                const result = try decoder.decodeAlloc(u8, allocator, tc.encoded);
                try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
                try std.testing.expectEqual(result.value, tc.value.u8);
            },
            .u16 => {
                const result = try decoder.decodeAlloc(u16, allocator, tc.encoded);
                try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
                try std.testing.expectEqual(result.value, tc.value.u16);
            },
            .u32 => {
                const result = try decoder.decodeAlloc(u32, allocator, tc.encoded);
                try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
                try std.testing.expectEqual(result.value, tc.value.u32);
            },
            .u64 => {
                const result = try decoder.decodeAlloc(u64, allocator, tc.encoded);
                try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
                try std.testing.expectEqual(result.value, tc.value.u64);
            },
            .u128 => {
                const result = try decoder.decodeAlloc(u128, allocator, tc.encoded);
                try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
                try std.testing.expectEqual(result.value, tc.value.u128);
            },
        }
    }
}

test "encode-and-decode-option" {
    const allocator = std.testing.allocator;

    const test_cases = [_]struct {
        value: ?bool,
        encoded: []const u8,
    }{
        .{ .value = false, .encoded = &[_]u8{ 0x01, 0x00 } },
        .{ .value = null, .encoded = &[_]u8{0x00} },
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc(?bool, allocator, tc.encoded);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqual(result.value, tc.value);
    }
}

test "encode-and-decode-string" {
    // Test both []const u8 and []u8 string types for SCALE encoding/decoding
    const allocator = std.testing.allocator;

    // Test cases for []const u8 (immutable strings)
    const const_test_cases = [_]struct {
        decoded: []const u8,
        encoded: []const u8,
    }{
        .{
            .decoded = "Hello World",
            .encoded = &[_]u8{ 0x2c, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64 },
        },
        .{
            .decoded = "",
            .encoded = &[_]u8{0x00},
        },
        .{
            .decoded = "A",
            .encoded = &[_]u8{ 0x04, 0x41 },
        },
        .{
            .decoded = "Hello",
            .encoded = &[_]u8{ 0x14, 0x48, 0x65, 0x6c, 0x6c, 0x6f },
        },
        .{
            .decoded = "This is a longer string for testing",
            .encoded = &[_]u8{ 0x8c, 0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x61, 0x20, 0x6c, 0x6f, 0x6e, 0x67, 0x65, 0x72, 0x20, 0x73, 0x74, 0x72, 0x69, 0x6e, 0x67, 0x20, 0x66, 0x6f, 0x72, 0x20, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67 },
        },
    };

    // Test cases for []u8 (mutable strings)
    const mutable_test_cases = [_]struct {
        decoded: []u8,
        encoded: []const u8,
    }{
        .{
            .decoded = try allocator.dupe(u8, "Hello World"),
            .encoded = &[_]u8{ 0x2c, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64 },
        },
        .{
            .decoded = try allocator.dupe(u8, ""),
            .encoded = &[_]u8{0x00},
        },
        .{
            .decoded = try allocator.dupe(u8, "Test"),
            .encoded = &[_]u8{ 0x10, 0x54, 0x65, 0x73, 0x74 },
        },
        .{
            .decoded = try allocator.dupe(u8, "Mutable String"),
            .encoded = &[_]u8{ 0x38, 0x4d, 0x75, 0x74, 0x61, 0x62, 0x6c, 0x65, 0x20, 0x53, 0x74, 0x72, 0x69, 0x6e, 0x67 },
        },
    };

    // Test []const u8 encoding and decoding
    for (const_test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.decoded);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc([]const u8, allocator, tc.encoded);
        defer allocator.free(result.value);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqualStrings(tc.decoded, result.value);
    }

    // Test []u8 encoding and decoding
    for (mutable_test_cases) |tc| {
        defer allocator.free(tc.decoded);

        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.decoded);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc([]u8, allocator, tc.encoded);
        defer allocator.free(result.value);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqualStrings(tc.decoded, result.value);
    }
}

test "encode-and-decode-bool" {
    const allocator = std.testing.allocator;
    const test_cases = [_]struct {
        value: bool,
        expected_encoding: []const u8,
    }{
        .{ .value = true, .expected_encoding = &[_]u8{0x01} },
        .{ .value = false, .expected_encoding = &[_]u8{0x00} },
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.expected_encoding, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc(bool, allocator, tc.expected_encoding);
        try std.testing.expectEqual(result.bytes_read, 1);
        try std.testing.expectEqual(result.value, tc.value);
    }
}
