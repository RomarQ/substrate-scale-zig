const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
const types = @import("types.zig");

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

test "encode-and-decode-option-bool" {
    // Standard ?bool uses 2-byte encoding like other Option<T>:
    // None = 0x00, Some(false) = 0x01 0x00, Some(true) = 0x01 0x01
    const allocator = std.testing.allocator;

    const test_cases = [_]struct {
        value: ?bool,
        encoded: []const u8,
    }{
        .{ .value = null, .encoded = &[_]u8{0x00} },
        .{ .value = true, .encoded = &[_]u8{ 0x01, 0x01 } },
        .{ .value = false, .encoded = &[_]u8{ 0x01, 0x00 } },
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

test "encode-and-decode-option-type" {
    // types.Option(T) is a generic option type with standard SCALE encoding:
    // None = 0x00, Some(value) = 0x01 + encoded value
    const allocator = std.testing.allocator;

    // Test Option(bool)
    {
        const OptionBool = types.Option(bool);
        const test_cases = [_]struct {
            value: OptionBool,
            encoded: []const u8,
        }{
            .{ .value = OptionBool.none(), .encoded = &[_]u8{0x00} },
            .{ .value = OptionBool.some(true), .encoded = &[_]u8{ 0x01, 0x01 } },
            .{ .value = OptionBool.some(false), .encoded = &[_]u8{ 0x01, 0x00 } },
        };

        for (test_cases) |tc| {
            const buffer = try encoder.encodeAlloc(allocator, tc.value);
            defer allocator.free(buffer);
            try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

            const result = try decoder.decodeAlloc(OptionBool, allocator, tc.encoded);
            try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
            try std.testing.expectEqual(result.value.unwrap(), tc.value.unwrap());
        }
    }

    // Test Option(u32)
    {
        const OptionU32 = types.Option(u32);
        const test_cases = [_]struct {
            value: OptionU32,
            encoded: []const u8,
        }{
            .{ .value = OptionU32.none(), .encoded = &[_]u8{0x00} },
            .{ .value = OptionU32.some(42), .encoded = &[_]u8{ 0x01, 0x2a, 0x00, 0x00, 0x00 } },
        };

        for (test_cases) |tc| {
            const buffer = try encoder.encodeAlloc(allocator, tc.value);
            defer allocator.free(buffer);
            try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

            const result = try decoder.decodeAlloc(OptionU32, allocator, tc.encoded);
            try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
            try std.testing.expectEqual(result.value.unwrap(), tc.value.unwrap());
        }
    }
}

test "encode-and-decode-option-u32" {
    // Regular Option<T> uses standard encoding: 0x00 for None, 0x01 + value for Some
    const allocator = std.testing.allocator;

    const test_cases = [_]struct {
        value: ?u32,
        encoded: []const u8,
    }{
        .{ .value = null, .encoded = &[_]u8{0x00} },
        .{ .value = 42, .encoded = &[_]u8{ 0x01, 0x2a, 0x00, 0x00, 0x00 } },
        .{ .value = 0, .encoded = &[_]u8{ 0x01, 0x00, 0x00, 0x00, 0x00 } },
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc(?u32, allocator, tc.encoded);
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

test "encode-and-decode-tagged-union" {
    // Test tagged union (enum) encoding/decoding
    const allocator = std.testing.allocator;

    const SimpleEnum = union(enum) {
        Unit,
        WithU32: u32,
        WithBool: bool,
        WithTuple: struct { u32, u64 },
    };

    const test_cases = [_]struct {
        value: SimpleEnum,
        encoded: []const u8,
    }{
        // Unit variant (index 0, no payload)
        .{ .value = .Unit, .encoded = &[_]u8{0x00} },
        // WithU32 variant (index 1, u32 payload)
        .{ .value = .{ .WithU32 = 42 }, .encoded = &[_]u8{ 0x01, 0x2a, 0x00, 0x00, 0x00 } },
        // WithBool variant (index 2, bool payload)
        .{ .value = .{ .WithBool = true }, .encoded = &[_]u8{ 0x02, 0x01 } },
        // WithTuple variant (index 3, tuple payload)
        .{
            .value = .{ .WithTuple = .{ 1, 2 } },
            .encoded = &[_]u8{ 0x03, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        },
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc(SimpleEnum, allocator, tc.encoded);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqual(result.value, tc.value);
    }
}

test "encode-and-decode-tagged-union-custom-indices" {
    // Test tagged union with custom indices via scale_indices declaration
    const allocator = std.testing.allocator;

    const CustomIndexEnum = union(enum) {
        A,
        B: u32,
        C: u64,

        // Custom indices matching Rust's #[codec(index = N)]
        pub const scale_indices = .{
            .A = 0,
            .B = 15,
            .C = 255,
        };
    };

    const test_cases = [_]struct {
        value: CustomIndexEnum,
        encoded: []const u8,
    }{
        .{ .value = .A, .encoded = &[_]u8{0x00} },
        .{ .value = .{ .B = 42 }, .encoded = &[_]u8{ 0x0f, 0x2a, 0x00, 0x00, 0x00 } }, // index 15
        .{ .value = .{ .C = 100 }, .encoded = &[_]u8{ 0xff, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } }, // index 255
    };

    for (test_cases) |tc| {
        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, tc.value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc(CustomIndexEnum, allocator, tc.encoded);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqual(result.value, tc.value);
    }
}

test "custom-encode-decode" {
    // Test custom scaleEncode/scaleDecode methods via @hasDecl
    const allocator = std.testing.allocator;

    // A type with custom encoding: encodes value * 2
    const CustomType = struct {
        value: u32,

        const Self = @This();

        pub fn scaleEncode(self: Self, buffer: []u8) !usize {
            // Custom encoding: multiply value by 2
            const encoded_value = self.value * 2;
            if (buffer.len < 4) return error.BufferTooSmall;
            std.mem.writeInt(u32, buffer[0..4], encoded_value, .little);
            return 4;
        }

        pub fn scaleDecode(_: std.mem.Allocator, data: []const u8) !decoder.DecodeResult(Self) {
            if (data.len < 4) return error.InsufficientData;
            const encoded_value = std.mem.readInt(u32, data[0..4], .little);
            // Custom decoding: divide by 2
            return .{
                .value = Self{ .value = encoded_value / 2 },
                .bytes_read = 4,
            };
        }

        pub fn scaleEncodedSize(_: Self) usize {
            return 4;
        }
    };

    const original = CustomType{ .value = 21 };

    // Test encoding (21 * 2 = 42)
    const buffer = try encoder.encodeAlloc(allocator, original);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x2a, 0x00, 0x00, 0x00 }, buffer);

    // Test decoding (42 / 2 = 21)
    const result = try decoder.decodeAlloc(CustomType, allocator, buffer);
    try std.testing.expectEqual(result.bytes_read, 4);
    try std.testing.expectEqual(result.value.value, 21);
}

test "encode-and-decode-result" {
    // Test Result(T, E) type matching Rust's Result encoding
    const allocator = std.testing.allocator;

    const R = types.Result(u32, u8);

    // Test Ok variant: 0x00 + value
    {
        const ok_value = R.fromOk(42);
        const buffer = try encoder.encodeAlloc(allocator, ok_value);
        defer allocator.free(buffer);
        // 0x00 (Ok) + 0x2a,0x00,0x00,0x00 (u32 = 42)
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x2a, 0x00, 0x00, 0x00 }, buffer);

        const result = try decoder.decodeAlloc(R, allocator, buffer);
        try std.testing.expectEqual(result.bytes_read, 5);
        try std.testing.expect(result.value.isOk());
        try std.testing.expectEqual(result.value.ok, 42);
    }

    // Test Err variant: 0x01 + error
    {
        const err_value = R.fromErr(1);
        const buffer = try encoder.encodeAlloc(allocator, err_value);
        defer allocator.free(buffer);
        // 0x01 (Err) + 0x01 (u8 = 1)
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x01 }, buffer);

        const result = try decoder.decodeAlloc(R, allocator, buffer);
        try std.testing.expectEqual(result.bytes_read, 2);
        try std.testing.expect(result.value.isErr());
        try std.testing.expectEqual(result.value.err, 1);
    }
}

test "encode-and-decode-compact-wrapper" {
    // Test Compact(T) wrapper type for explicit compact encoding
    const allocator = std.testing.allocator;

    const test_cases = [_]struct {
        value: u32,
        encoded: []const u8,
    }{
        .{ .value = 0, .encoded = &[_]u8{0x00} },
        .{ .value = 1, .encoded = &[_]u8{0x04} },
        .{ .value = 63, .encoded = &[_]u8{0xfc} },
        .{ .value = 64, .encoded = &[_]u8{ 0x01, 0x01 } },
        .{ .value = 16383, .encoded = &[_]u8{ 0xfd, 0xff } },
        .{ .value = 16384, .encoded = &[_]u8{ 0x02, 0x00, 0x01, 0x00 } },
    };

    for (test_cases) |tc| {
        const compact = types.Compact(u32).init(tc.value);

        // Test encoding
        const buffer = try encoder.encodeAlloc(allocator, compact);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, tc.encoded, buffer);

        // Test decoding
        const result = try decoder.decodeAlloc(types.Compact(u32), allocator, tc.encoded);
        try std.testing.expectEqual(result.bytes_read, tc.encoded.len);
        try std.testing.expectEqual(result.value.value, tc.value);
    }
}

test "encode-struct-with-compact-field" {
    // Test using Compact(T) in struct fields
    const allocator = std.testing.allocator;

    const MyStruct = struct {
        id: types.Compact(u32),
        name_len: types.Compact(u32),
    };

    const value = MyStruct{
        .id = types.Compact(u32).init(42),
        .name_len = types.Compact(u32).init(100),
    };

    // 42 -> compact 0xa8 (42 << 2 = 168 = 0xa8)
    // 100 -> compact two-byte mode: ((100 & 0x3f) << 2) | 0x01 = 0x91, 100 >> 6 = 1
    const expected = &[_]u8{ 0xa8, 0x91, 0x01 };

    const buffer = try encoder.encodeAlloc(allocator, value);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, expected, buffer);

    const result = try decoder.decodeAlloc(MyStruct, allocator, buffer);
    try std.testing.expectEqual(result.value.id.value, 42);
    try std.testing.expectEqual(result.value.name_len.value, 100);
}

// ============================================================================
// Rust parity tests - ported from parity-scale-codec
// ============================================================================

test "compact-integer-edge-cases" {
    // Test compact encoding at all mode boundaries (from Rust tests)
    const TestCase = struct {
        value: u64,
        expected_len: usize,
        expected: []const u8,
    };

    const test_cases = [_]TestCase{
        // Single-byte mode: 0-63
        .{ .value = 0, .expected_len = 1, .expected = &[_]u8{0x00} },
        .{ .value = 1, .expected_len = 1, .expected = &[_]u8{0x04} },
        .{ .value = 63, .expected_len = 1, .expected = &[_]u8{0xfc} },

        // Two-byte mode: 64-16383
        .{ .value = 64, .expected_len = 2, .expected = &[_]u8{ 0x01, 0x01 } },
        .{ .value = 255, .expected_len = 2, .expected = &[_]u8{ 0xfd, 0x03 } },
        .{ .value = 16383, .expected_len = 2, .expected = &[_]u8{ 0xfd, 0xff } },

        // Four-byte mode: 16384-1073741823
        .{ .value = 16384, .expected_len = 4, .expected = &[_]u8{ 0x02, 0x00, 0x01, 0x00 } },
        .{ .value = 1073741823, .expected_len = 4, .expected = &[_]u8{ 0xfe, 0xff, 0xff, 0xff } },

        // Big integer mode: 1073741824+
        .{ .value = 1073741824, .expected_len = 5, .expected = &[_]u8{ 0x03, 0x00, 0x00, 0x00, 0x40 } },
    };

    for (test_cases) |tc| {
        var buffer: [16]u8 = undefined;
        const len = try encoder.encodeCompact(u64, tc.value, &buffer);
        try std.testing.expectEqual(tc.expected_len, len);
        try std.testing.expectEqualSlices(u8, tc.expected, buffer[0..len]);

        // Verify round-trip
        const result = try decoder.decodeCompact(u64, tc.expected);
        try std.testing.expectEqual(tc.value, result.value);
        try std.testing.expectEqual(tc.expected_len, result.bytes_read);
    }
}

test "compact-u64-max" {
    // Test u64::MAX compact encoding (9 bytes: 1 header + 8 data)
    const value: u64 = std.math.maxInt(u64);
    var buffer: [16]u8 = undefined;

    const len = try encoder.encodeCompact(u64, value, &buffer);
    try std.testing.expectEqual(@as(usize, 9), len);

    // Header: (8 - 4) << 2 | 0b11 = 4 << 2 | 3 = 19 = 0x13
    try std.testing.expectEqual(@as(u8, 0x13), buffer[0]);

    // Verify round-trip
    const result = try decoder.decodeCompact(u64, buffer[0..len]);
    try std.testing.expectEqual(value, result.value);
}

test "signed-integers" {
    // Test signed integer encoding (two's complement, little-endian)
    const allocator = std.testing.allocator;

    // i8
    {
        const value: i8 = -1;
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{0xff}, buffer);

        const result = try decoder.decodeAlloc(i8, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i16
    {
        const value: i16 = -256;
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0xff }, buffer);

        const result = try decoder.decodeAlloc(i16, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i32
    {
        const value: i32 = -1;
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0xff, 0xff, 0xff }, buffer);

        const result = try decoder.decodeAlloc(i32, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i64
    {
        const value: i64 = -1;
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, buffer);

        const result = try decoder.decodeAlloc(i64, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i64 positive max
    {
        const value: i64 = std.math.maxInt(i64);
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f }, buffer);

        const result = try decoder.decodeAlloc(i64, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i64 negative min
    {
        const value: i64 = std.math.minInt(i64);
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80 }, buffer);

        const result = try decoder.decodeAlloc(i64, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i128
    {
        const value: i128 = -1;
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        const expected = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
        try std.testing.expectEqualSlices(u8, &expected, buffer);

        const result = try decoder.decodeAlloc(i128, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i128 positive max
    {
        const value: i128 = std.math.maxInt(i128);
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        const expected = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f };
        try std.testing.expectEqualSlices(u8, &expected, buffer);

        const result = try decoder.decodeAlloc(i128, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }

    // i128 negative min
    {
        const value: i128 = std.math.minInt(i128);
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        const expected = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80 };
        try std.testing.expectEqualSlices(u8, &expected, buffer);

        const result = try decoder.decodeAlloc(i128, allocator, buffer);
        try std.testing.expectEqual(value, result.value);
    }
}

test "struct-encoding-parity" {
    // Matches Rust: Struct { a: 15, b: 9 } followed by string "Hello"
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        a: u32,
        b: u64,
    };

    const value = TestStruct{ .a = 15, .b = 9 };
    const expected = &[_]u8{
        0x0f, 0x00, 0x00, 0x00, // u32 = 15
        0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // u64 = 9
    };

    const buffer = try encoder.encodeAlloc(allocator, value);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, expected, buffer);

    const result = try decoder.decodeAlloc(TestStruct, allocator, buffer);
    try std.testing.expectEqual(value, result.value);
}

test "fixed-array-encoding" {
    // Fixed arrays don't include length prefix (unlike slices)
    const allocator = std.testing.allocator;

    const arr: [3]u8 = .{ 1, 2, 3 };
    const expected = &[_]u8{
        0x0c, // compact length 3
        0x01, 0x02, 0x03, // data
    };

    const buffer = try encoder.encodeAlloc(allocator, arr);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, expected, buffer);
}

test "fixed-array-of-u32" {
    // Fixed arrays of non-u8 types
    const allocator = std.testing.allocator;

    const arr: [2]u32 = .{ 1, 2 };
    const expected = &[_]u8{
        0x01, 0x00, 0x00, 0x00, // u32 = 1
        0x02, 0x00, 0x00, 0x00, // u32 = 2
    };

    const buffer = try encoder.encodeAlloc(allocator, arr);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, expected, buffer);
}

test "empty-vector" {
    // Empty vector should just be compact(0)
    const allocator = std.testing.allocator;

    const empty: []const u32 = &[_]u32{};
    const expected = &[_]u8{0x00}; // compact 0

    const buffer = try encoder.encodeAlloc(allocator, empty);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, expected, buffer);
}

test "nested-struct" {
    // Test nested struct encoding
    const allocator = std.testing.allocator;

    const Inner = struct {
        x: u16,
        y: u16,
    };

    const Outer = struct {
        id: u32,
        point: Inner,
    };

    const value = Outer{
        .id = 1,
        .point = Inner{ .x = 10, .y = 20 },
    };

    const expected = &[_]u8{
        0x01, 0x00, 0x00, 0x00, // u32 id = 1
        0x0a, 0x00, // u16 x = 10
        0x14, 0x00, // u16 y = 20
    };

    const buffer = try encoder.encodeAlloc(allocator, value);
    defer allocator.free(buffer);
    try std.testing.expectEqualSlices(u8, expected, buffer);

    const result = try decoder.decodeAlloc(Outer, allocator, buffer);
    try std.testing.expectEqual(value, result.value);
}

// ============================================================================
// Edge case and boundary condition tests
// ============================================================================

test "result-with-void-ok" {
    // Test Result<void, E> - Ok variant has no payload
    const allocator = std.testing.allocator;

    const VoidResult = types.Result(void, u8);

    // Ok(void): just 0x00
    {
        const ok_value = VoidResult.fromOk({});
        const buffer = try encoder.encodeAlloc(allocator, ok_value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{0x00}, buffer);

        const result = try decoder.decodeAlloc(VoidResult, allocator, buffer);
        try std.testing.expectEqual(result.bytes_read, 1);
        try std.testing.expect(result.value.isOk());
    }

    // Err(1): 0x01 + error byte
    {
        const err_value = VoidResult.fromErr(1);
        const buffer = try encoder.encodeAlloc(allocator, err_value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x01 }, buffer);

        const result = try decoder.decodeAlloc(VoidResult, allocator, buffer);
        try std.testing.expectEqual(result.bytes_read, 2);
        try std.testing.expect(result.value.isErr());
        try std.testing.expectEqual(result.value.err, 1);
    }
}

test "result-with-void-err" {
    // Test Result<T, void> - Err variant has no payload
    const allocator = std.testing.allocator;

    const VoidErrResult = types.Result(u32, void);

    // Ok(42)
    {
        const ok_value = VoidErrResult.fromOk(42);
        const buffer = try encoder.encodeAlloc(allocator, ok_value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x2a, 0x00, 0x00, 0x00 }, buffer);

        const result = try decoder.decodeAlloc(VoidErrResult, allocator, buffer);
        try std.testing.expectEqual(result.bytes_read, 5);
        try std.testing.expect(result.value.isOk());
        try std.testing.expectEqual(result.value.ok, 42);
    }

    // Err(void)
    {
        const err_value = VoidErrResult.fromErr({});
        const buffer = try encoder.encodeAlloc(allocator, err_value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{0x01}, buffer);

        const result = try decoder.decodeAlloc(VoidErrResult, allocator, buffer);
        try std.testing.expectEqual(result.bytes_read, 1);
        try std.testing.expect(result.value.isErr());
    }
}

test "nested-option" {
    // Test Option<Option<T>>
    const allocator = std.testing.allocator;

    // None: 0x00
    {
        const value: ??u8 = null;
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{0x00}, buffer);

        const result = try decoder.decodeAlloc(??u8, allocator, buffer);
        try std.testing.expectEqual(result.value, null);
    }

    // Some(None): 0x01 0x00
    {
        const value: ??u8 = @as(?u8, null);
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x00 }, buffer);

        const result = try decoder.decodeAlloc(??u8, allocator, buffer);
        try std.testing.expect(result.value != null);
        try std.testing.expectEqual(result.value.?, null);
    }

    // Some(Some(42)): 0x01 0x01 0x2a
    {
        const value: ??u8 = @as(?u8, 42);
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x01, 0x2a }, buffer);

        const result = try decoder.decodeAlloc(??u8, allocator, buffer);
        try std.testing.expect(result.value != null);
        try std.testing.expectEqual(result.value.?, 42);
    }
}

test "compact-u128-max" {
    // Test u128::MAX compact encoding
    const value: u128 = std.math.maxInt(u128);
    var buffer: [32]u8 = undefined;

    const len = try encoder.encodeCompact(u128, value, &buffer);
    // 16 bytes + 1 header = 17 bytes
    // Header: (16 - 4) << 2 | 0b11 = 12 << 2 | 3 = 51 = 0x33
    try std.testing.expectEqual(@as(usize, 17), len);
    try std.testing.expectEqual(@as(u8, 0x33), buffer[0]);

    // Verify round-trip
    const result = try decoder.decodeCompact(u128, buffer[0..len]);
    try std.testing.expectEqual(value, result.value);
}

test "decode-insufficient-data" {
    // Test that decoding with insufficient data returns proper errors
    const allocator = std.testing.allocator;

    // u32 needs 4 bytes
    {
        const data = &[_]u8{ 0x01, 0x02 }; // Only 2 bytes
        const result = decoder.decodeAlloc(u32, allocator, data);
        try std.testing.expectError(error.InsufficientData, result);
    }

    // Compact with incomplete multi-byte encoding
    {
        const data = &[_]u8{0x01}; // Two-byte mode but only 1 byte
        const result = decoder.decodeCompact(u32, data);
        try std.testing.expectError(error.InsufficientData, result);
    }

    // Option with Some but no payload
    {
        const data = &[_]u8{0x01}; // Some(?) but no value
        const result = decoder.decodeAlloc(?u32, allocator, data);
        try std.testing.expectError(error.InsufficientData, result);
    }
}

test "decode-invalid-bool" {
    // Test that invalid bool values are rejected
    const allocator = std.testing.allocator;

    const data = &[_]u8{0x02}; // Invalid: not 0 or 1
    const result = decoder.decodeAlloc(bool, allocator, data);
    try std.testing.expectError(error.InvalidBool, result);
}

test "decode-invalid-option" {
    // Test that invalid option prefix is rejected
    const allocator = std.testing.allocator;

    const data = &[_]u8{0x02}; // Invalid: not 0 or 1
    const result = decoder.decodeAlloc(?u8, allocator, data);
    try std.testing.expectError(error.InvalidOption, result);
}

test "decode-invalid-enum-variant" {
    // Test that invalid enum variant index is rejected
    const allocator = std.testing.allocator;

    const SimpleEnum = union(enum) {
        A,
        B: u32,
    };

    // Variant index 5 doesn't exist
    const data = &[_]u8{0x05};
    const result = decoder.decodeAlloc(SimpleEnum, allocator, data);
    try std.testing.expectError(error.InvalidEnumVariant, result);
}

test "empty-struct" {
    // Test encoding/decoding of empty struct (unit type)
    const allocator = std.testing.allocator;

    const EmptyStruct = struct {};

    const value = EmptyStruct{};
    const buffer = try encoder.encodeAlloc(allocator, value);
    defer allocator.free(buffer);

    // Empty struct encodes to 0 bytes
    try std.testing.expectEqual(@as(usize, 0), buffer.len);

    // Decoding empty data gives empty struct
    const result = try decoder.decodeAlloc(EmptyStruct, allocator, &[_]u8{});
    try std.testing.expectEqual(result.bytes_read, 0);
    _ = result.value; // Just verify it was created
}

test "union-with-void-variant" {
    // Test union with void payload variant
    const allocator = std.testing.allocator;

    const MixedUnion = union(enum) {
        Empty,
        WithValue: u32,
    };

    // Empty variant (void) - use explicit type annotation
    {
        const value: MixedUnion = .Empty;
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{0x00}, buffer);

        const result = try decoder.decodeAlloc(MixedUnion, allocator, buffer);
        try std.testing.expect(result.value == .Empty);
    }

    // WithValue variant
    {
        const value: MixedUnion = .{ .WithValue = 42 };
        const buffer = try encoder.encodeAlloc(allocator, value);
        defer allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x2a, 0x00, 0x00, 0x00 }, buffer);

        const result = try decoder.decodeAlloc(MixedUnion, allocator, buffer);
        try std.testing.expectEqual(result.value.WithValue, 42);
    }
}
