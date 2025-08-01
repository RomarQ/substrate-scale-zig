const std = @import("std");
const util = @import("util.zig");

pub const EncodeError = error{
    BufferTooSmall,
    InvalidCompactValue,
};

// Encode with allocation.
pub fn encodeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    const size = try util.calculateEncodedSize(value);
    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    const written = try encode(value, buffer);
    std.debug.assert(written == size);

    return buffer;
}

fn encodeBool(value: bool, buffer: []u8) !usize {
    if (buffer.len < 1) return error.BufferTooSmall;
    buffer[0] = if (value) 0x01 else 0x00;
    return 1;
}

fn encodeUnsigned(comptime T: type, value: T, buffer: []u8) !usize {
    const size = @sizeOf(T);
    if (buffer.len < size) return error.BufferTooSmall;

    if (size == 1) {
        buffer[0] = @intCast(value);
    } else {
        std.mem.writeInt(T, buffer[0..size], value, .little);
    }
    return size;
}

fn encodeSigned(comptime T: type, value: T, buffer: []u8) !usize {
    const size = @sizeOf(T);
    if (buffer.len < size) return error.BufferTooSmall;

    if (size == 1) {
        buffer[0] = @bitCast(value);
    } else {
        std.mem.writeInt(T, buffer[0..size], value, .little);
    }
    return size;
}

fn encodeByteSlice(value: []const u8, buffer: []u8) !usize {
    var offset: usize = 0;

    // Encode length as compact
    const len_bytes = try encodeCompact(u32, @intCast(value.len), buffer[offset..]);
    offset += len_bytes;

    // Encode string data
    if (buffer.len < offset + value.len) return error.BufferTooSmall;
    @memcpy(buffer[offset .. offset + value.len], value);
    offset += value.len;

    return offset;
}

fn encodeOption(comptime T: type, value: ?T, buffer: []u8, encoder: anytype) !usize {
    if (value) |v| {
        if (buffer.len < 1) return error.BufferTooSmall;
        buffer[0] = 0x01;
        const encoded_bytes = try encoder(v, buffer[1..]);
        return 1 + encoded_bytes;
    } else {
        if (buffer.len < 1) return error.BufferTooSmall;
        buffer[0] = 0x00;
        return 1;
    }
}

fn encodeArray(comptime T: type, value: []const T, buffer: []u8, encoder: anytype) !usize {
    var offset: usize = 0;

    // Encode length as compact
    const len_bytes = try encodeCompact(u32, @intCast(value.len), buffer[offset..]);
    offset += len_bytes;

    // Encode array elements
    for (value) |item| {
        const encoded_bytes = try encoder(item, buffer[offset..]);
        offset += encoded_bytes;
    }

    return offset;
}

fn encodeFixedArray(comptime T: type, comptime N: usize, value: [N]T, buffer: []u8, encoder: anytype) !usize {
    var offset: usize = 0;

    // Fixed arrays don't encode their length
    for (value) |item| {
        const encoded_bytes = try encoder(item, buffer[offset..]);
        offset += encoded_bytes;
    }

    return offset;
}

fn encodeTuple(value: anytype, buffer: []u8) !usize {
    var offset: usize = 0;
    const fields = std.meta.fields(@TypeOf(value));

    inline for (fields) |field| {
        const field_value = @field(value, field.name);
        const encoded_bytes = try encode(field_value, buffer[offset..]);
        offset += encoded_bytes;
    }

    return offset;
}

fn encodeCompact(comptime T: type, value: T, buffer: []u8) !usize {
    const v = @as(u128, value);

    if (v < 64) {
        // Single byte mode
        if (buffer.len < 1) return error.BufferTooSmall;
        buffer[0] = @as(u8, @intCast((v << 2) | 0b00));
        return 1;
    } else if (v < 16384) {
        // Two byte mode
        if (buffer.len < 2) return error.BufferTooSmall;
        buffer[0] = @as(u8, @intCast(((v & 0x3f) << 2) | 0b01));
        buffer[1] = @as(u8, @intCast((v >> 6) & 0xff));
        return 2;
    } else if (v < 1073741824) {
        // Four byte mode
        if (buffer.len < 4) return error.BufferTooSmall;
        buffer[0] = @as(u8, @intCast(((v & 0x3f) << 2) | 0b10));
        buffer[1] = @as(u8, @intCast((v >> 6) & 0xff));
        buffer[2] = @as(u8, @intCast((v >> 14) & 0xff));
        buffer[3] = @as(u8, @intCast((v >> 22) & 0xff));
        return 4;
    } else {
        // Big integer mode
        var bytes_needed: usize = 0;
        var temp = v;
        while (temp > 0) : (temp >>= 8) {
            bytes_needed += 1;
        }

        if (bytes_needed > 67) return error.InvalidCompactValue;
        if (buffer.len < bytes_needed + 1) return error.BufferTooSmall;

        buffer[0] = @as(u8, @intCast(((bytes_needed - 4) << 2) | 0b11));
        var i: usize = 0;
        while (i < bytes_needed) : (i += 1) {
            buffer[i + 1] = @as(u8, @intCast((v >> @intCast(i * 8)) & 0xFF));
        }
        return bytes_needed + 1;
    }
}

// Generic encode function that dispatches to the appropriate encoder
fn encode(value: anytype, buffer: []u8) !usize {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .bool => encodeBool(value, buffer),
        .int => |info| {
            if (info.signedness == .unsigned) {
                return encodeUnsigned(T, value, buffer);
            } else {
                return encodeSigned(T, value, buffer);
            }
        },
        .array => |info| {
            if (info.child == u8) {
                return encodeByteSlice(&value, buffer);
            } else {
                return encodeFixedArray(info.child, info.len, value, buffer, encode);
            }
        },
        .pointer => |info| {
            if (info.size == .slice) {
                return encodeArray(info.child, value, buffer, encode);
            } else if (info.size == .one and @typeInfo(info.child) == .array) {
                // Handle pointers to arrays (like string literals)
                const array_info = @typeInfo(info.child).array;
                // Convert pointer to array into a slice
                const slice = value[0..array_info.len];
                return encodeFixedArray(info.child, info.len, slice, buffer, encode);
            }

            std.debug.print("Unsupported type: {s}\n", .{@typeName(T)});
            return error.UnsupportedType;
        },
        .optional => |info| {
            return encodeOption(info.child, value, buffer, encode);
        },
        .@"struct" => {
            return encodeTuple(value, buffer);
        },
        else => {
            std.debug.print("Unsupported type: {s}\n", .{@typeName(T)});
            return error.UnsupportedType;
        },
    };
}
