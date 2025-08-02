const std = @import("std");

pub fn DecodeResult(comptime T: type) type {
    return struct {
        value: T,
        bytes_read: usize,
    };
}

pub const DecodeError = error{
    InsufficientData,
    BigIntegerNotSupported,
    InvalidBool,
    InvalidOption,
    UnexpectedEndOfData,
};

// Decode with allocation.
pub fn decodeAlloc(comptime T: type, allocator: std.mem.Allocator, data: []const u8) !DecodeResult(T) {
    return switch (@typeInfo(T)) {
        .bool => try decodeBool(data),
        .int => |info| {
            if (info.signedness == .unsigned) {
                return decodeUnsigned(T, data);
            } else {
                return decodeSigned(T, data);
            }
        },
        .optional => |info| decodeOption(info.child, allocator, data, decodeAlloc),
        .pointer => |info| {
            if (info.size == .slice) {
                if (info.child == u8) {
                    // Handle string slices - decode as []u8 and convert if needed
                    const result = try decodeSlice(u8, allocator, data, decodeAlloc);
                    if (T == []const u8) {
                        // Convert []u8 to []const u8
                        return .{ .value = result.value, .bytes_read = result.bytes_read };
                    } else {
                        return result;
                    }
                } else {
                    return decodeSlice(info.child, allocator, data, decodeAlloc);
                }
            } else {
                return error.UnsupportedType;
            }
        },
        .array => |info| {
            return decodeSlice(info.child, allocator, data, decodeAlloc);
        },
        .@"struct" => {
            return decodeTuple(T, allocator, data);
        },
        else => error.UnsupportedType,
    };
}

pub fn decodeCompact(comptime T: type, data: []const u8) !DecodeResult(T) {
    if (data.len == 0) return error.InsufficientData;

    const first_byte = data[0];
    const mode = first_byte & 0b11;

    switch (mode) {
        0b00 => {
            // Single byte mode
            const value = first_byte >> 2;
            return .{ .value = @intCast(value), .bytes_read = 1 };
        },
        0b01 => {
            // Two byte mode
            if (data.len < 2) return error.InsufficientData;
            const value = @as(u16, first_byte >> 2) | (@as(u16, data[1]) << 6);
            return .{ .value = @intCast(value), .bytes_read = 2 };
        },
        0b10 => {
            // Four byte mode
            if (data.len < 4) return error.InsufficientData;
            const value = @as(u32, first_byte >> 2) |
                (@as(u32, data[1]) << 6) |
                (@as(u32, data[2]) << 14) |
                (@as(u32, data[3]) << 22);
            return .{ .value = @intCast(value), .bytes_read = 4 };
        },
        0b11 => {
            // Big integer mode
            const byte_len = (first_byte >> 2) + 4;
            if (data.len < byte_len + 1) return error.InsufficientData;

            // For types smaller than the encoded bytes, we need to check if the value fits
            if (byte_len > @sizeOf(T)) {
                // Check if the extra bytes are all zero (value fits in type T)
                var i: usize = @sizeOf(T);
                while (i < byte_len) : (i += 1) {
                    if (data[i + 1] != 0) return error.BigIntegerNotSupported;
                }
            }

            var value: T = 0;
            var i: usize = 0;
            const max_bytes = @min(byte_len, @sizeOf(T));
            while (i < max_bytes) : (i += 1) {
                value |= @as(T, data[i + 1]) << @intCast(i * 8);
            }
            return .{ .value = value, .bytes_read = byte_len + 1 };
        },
        else => unreachable,
    }
}

pub fn decodeSlice(comptime T: type, allocator: std.mem.Allocator, data: []const u8, decoder: anytype) !DecodeResult(if (T == u8) []u8 else []T) {
    const length = try decodeCompact(u32, data);
    var offset = length.bytes_read;

    if (T == u8) {
        // For strings, just copy the raw bytes
        const end = offset + length.value;
        if (data.len < end) return error.InsufficientData;

        const duped = try allocator.dupe(u8, data[offset..end]);
        return .{
            .value = duped,
            .bytes_read = end,
        };
    } else {
        // For other types, decode each element individually
        var items = try allocator.alloc(T, length.value);
        errdefer allocator.free(items);

        var i: usize = 0;
        while (i < length.value) : (i += 1) {
            if (offset >= data.len) return error.UnexpectedEndOfData;
            // Use function parameter introspection to check the decoder signature
            const decoder_info = @typeInfo(@TypeOf(decoder));
            const is_allocator_first_param = decoder_info.@"fn".params.len == 2 and
                decoder_info.@"fn".params[0].type orelse void == std.mem.Allocator;
            const is_type_first_param = decoder_info.@"fn".params.len == 3 and
                decoder_info.@"fn".params[0].type orelse void == type;
            const result = if (is_allocator_first_param)
                try decoder(allocator, data[offset..])
            else if (is_type_first_param)
                try decoder(T, allocator, data[offset..])
            else
                try decoder(data[offset..]);
            items[i] = result.value;
            offset += result.bytes_read;
        }

        return .{ .value = items, .bytes_read = offset };
    }
}

pub fn decodeBool(data: []const u8) !DecodeResult(bool) {
    if (data.len == 0) return error.InsufficientData;

    return switch (data[0]) {
        0x00 => .{ .value = false, .bytes_read = 1 },
        0x01 => .{ .value = true, .bytes_read = 1 },
        else => error.InvalidBool,
    };
}

pub fn decodeOption(comptime T: type, allocator: std.mem.Allocator, data: []const u8, decoder: anytype) !DecodeResult(?T) {
    if (data.len == 0) return error.InsufficientData;

    return switch (data[0]) {
        0x00 => .{ .value = null, .bytes_read = 1 },
        0x01 => {
            // Use function parameter introspection to check if the first parameter is an allocator
            const decoder_info = @typeInfo(@TypeOf(decoder));
            const is_allocator_first_param = decoder_info.@"fn".params.len == 2 and
                decoder_info.@"fn".params[0].type orelse void == std.mem.Allocator;
            const is_type_first_param = decoder_info.@"fn".params.len == 3 and
                decoder_info.@"fn".params[0].type orelse void == type;
            const result = if (is_allocator_first_param)
                try decoder(allocator, data[1..])
            else if (is_type_first_param)
                try decoder(T, allocator, data[1..])
            else
                try decoder(data[1..]);
            return .{ .value = result.value, .bytes_read = 1 + result.bytes_read };
        },
        else => error.InvalidOption,
    };
}

pub fn decodeUnsigned(comptime T: type, data: []const u8) !DecodeResult(T) {
    const size = @sizeOf(T);
    if (data.len < size) return error.InsufficientData;
    const value = if (size == 1)
        @as(T, data[0])
    else
        std.mem.readInt(T, data[0..size], .little);
    return .{ .value = value, .bytes_read = size };
}

pub fn decodeSigned(comptime T: type, data: []const u8) !DecodeResult(T) {
    const size = @sizeOf(T);
    if (data.len < size) return error.InsufficientData;
    const value = if (size == 1)
        @as(T, @intCast(data[0]))
    else
        std.mem.readInt(T, data[0..size], .little);
    return .{ .value = value, .bytes_read = size };
}

fn decodeTuple(comptime T: type, allocator: std.mem.Allocator, data: []const u8) !DecodeResult(T) {
    var result: T = undefined;
    var offset: usize = 0;

    const fields = std.meta.fields(T);
    inline for (fields) |field| {
        if (offset >= data.len) return error.UnexpectedEndOfData;

        const field_result = try decodeAlloc(field.type, allocator, data[offset..]);
        @field(result, field.name) = field_result.value;
        offset += field_result.bytes_read;
    }

    return .{ .value = result, .bytes_read = offset };
}
