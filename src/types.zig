const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
const util = @import("util.zig");

/// SCALE-compatible Result type matching Rust's Result<T, E> encoding.
/// - Ok(value): 0x00 + encoded value
/// - Err(error): 0x01 + encoded error
pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        ok: T,
        err: E,

        const Self = @This();

        pub fn scaleEncode(self: Self, buffer: []u8) !usize {
            var offset: usize = 0;

            switch (self) {
                .ok => |value| {
                    if (buffer.len < 1) return error.BufferTooSmall;
                    buffer[0] = 0x00;
                    offset += 1;
                    if (T != void) {
                        offset += try encoder.encode(value, buffer[offset..]);
                    }
                },
                .err => |err_value| {
                    if (buffer.len < 1) return error.BufferTooSmall;
                    buffer[0] = 0x01;
                    offset += 1;
                    if (E != void) {
                        offset += try encoder.encode(err_value, buffer[offset..]);
                    }
                },
            }

            return offset;
        }

        pub fn scaleDecode(allocator: std.mem.Allocator, data: []const u8) !decoder.DecodeResult(Self) {
            if (data.len < 1) return error.InsufficientData;

            const variant = data[0];
            const offset: usize = 1;

            return switch (variant) {
                0x00 => {
                    if (T == void) {
                        return .{ .value = Self{ .ok = {} }, .bytes_read = offset };
                    }
                    const result = try decoder.decodeAlloc(T, allocator, data[offset..]);
                    return .{
                        .value = Self{ .ok = result.value },
                        .bytes_read = offset + result.bytes_read,
                    };
                },
                0x01 => {
                    if (E == void) {
                        return .{ .value = Self{ .err = {} }, .bytes_read = offset };
                    }
                    const result = try decoder.decodeAlloc(E, allocator, data[offset..]);
                    return .{
                        .value = Self{ .err = result.value },
                        .bytes_read = offset + result.bytes_read,
                    };
                },
                else => error.InvalidResultVariant,
            };
        }

        pub fn scaleEncodedSize(self: Self) usize {
            return 1 + switch (self) {
                .ok => |v| if (T == void) 0 else util.calculateEncodedSize(v) catch 0,
                .err => |e| if (E == void) 0 else util.calculateEncodedSize(e) catch 0,
            };
        }

        /// Helper to create Ok variant
        pub fn fromOk(value: T) Self {
            return Self{ .ok = value };
        }

        /// Helper to create Err variant
        pub fn fromErr(value: E) Self {
            return Self{ .err = value };
        }

        /// Check if this is an Ok variant
        pub fn isOk(self: Self) bool {
            return self == .ok;
        }

        /// Check if this is an Err variant
        pub fn isErr(self: Self) bool {
            return self == .err;
        }
    };
}

/// Wrapper type for compact integer encoding.
/// Use this to explicitly encode a field as a compact integer.
pub fn Compact(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn scaleEncode(self: Self, buffer: []u8) !usize {
            return encoder.encodeCompact(T, self.value, buffer);
        }

        pub fn scaleDecode(_: std.mem.Allocator, data: []const u8) !decoder.DecodeResult(Self) {
            const result = try decoder.decodeCompact(T, data);
            return .{
                .value = Self{ .value = result.value },
                .bytes_read = result.bytes_read,
            };
        }

        pub fn scaleEncodedSize(self: Self) usize {
            return util.calculateCompactSize(@as(u128, self.value));
        }
    };
}

/// Generic Option type with standard SCALE encoding.
/// - None: 0x00
/// - Some(value): 0x01 + encoded value
pub fn Option(comptime T: type) type {
    return struct {
        value: ?T,

        const Self = @This();

        pub fn none() Self {
            return .{ .value = null };
        }

        pub fn some(v: T) Self {
            return .{ .value = v };
        }

        pub fn scaleEncode(self: Self, buffer: []u8) !usize {
            if (self.value) |v| {
                if (buffer.len < 1) return error.BufferTooSmall;
                buffer[0] = 0x01;
                const encoded_bytes = try encoder.encode(v, buffer[1..]);
                return 1 + encoded_bytes;
            } else {
                if (buffer.len < 1) return error.BufferTooSmall;
                buffer[0] = 0x00;
                return 1;
            }
        }

        pub fn scaleDecode(allocator: std.mem.Allocator, data: []const u8) !decoder.DecodeResult(Self) {
            if (data.len < 1) return error.InsufficientData;
            return switch (data[0]) {
                0x00 => .{ .value = Self{ .value = null }, .bytes_read = 1 },
                0x01 => {
                    const result = try decoder.decodeAlloc(T, allocator, data[1..]);
                    return .{
                        .value = Self{ .value = result.value },
                        .bytes_read = 1 + result.bytes_read,
                    };
                },
                else => error.InvalidOption,
            };
        }

        pub fn scaleEncodedSize(self: Self) usize {
            return 1 + if (self.value) |v| (util.calculateEncodedSize(v) catch 0) else 0;
        }

        pub fn unwrap(self: Self) ?T {
            return self.value;
        }

        pub fn isSome(self: Self) bool {
            return self.value != null;
        }

        pub fn isNone(self: Self) bool {
            return self.value == null;
        }
    };
}
