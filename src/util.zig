const std = @import("std");

pub fn calculateEncodedSize(value: anytype) !usize {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .bool => 1,
        .int => |info| info.bits / 8,
        .array => |info| {
            if (info.child == u8) {
                return calculateCompactSize(@intCast(info.len)) + info.len;
            } else {
                var size: usize = 0;
                for (value) |item| {
                    size += try calculateEncodedSize(item);
                }
                return size;
            }
        },
        .pointer => |info| {
            if (info.size == .slice) {
                if (info.child == u8) {
                    return calculateCompactSize(@intCast(value.len)) + value.len;
                } else {
                    var size = calculateCompactSize(@intCast(value.len));
                    for (value) |item| {
                        size += try calculateEncodedSize(item);
                    }
                    return size;
                }
            } else if (info.size == .one and @typeInfo(info.child) == .array) {
                // Handle pointers to arrays (like string literals)
                const array_info = @typeInfo(info.child).array;
                if (array_info.child == u8) {
                    return calculateCompactSize(@intCast(array_info.len)) + array_info.len;
                } else {
                    var size = calculateCompactSize(@intCast(array_info.len));
                    for (value) |item| {
                        size += try calculateEncodedSize(item);
                    }
                    return size;
                }
            }

            std.debug.print("Unsupported type: {s}, {any}\n", .{ @typeName(T), @typeInfo(T) });
            return error.UnsupportedType;
        },
        .optional => {
            const base_size = 1;
            return base_size + if (value) |v| try calculateEncodedSize(v) else 0;
        },
        .@"struct" => {
            var size: usize = 0;
            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const field_value = @field(value, field.name);
                size += try calculateEncodedSize(field_value);
            }
            return size;
        },
        else => {
            std.debug.print("Unsupported type: {s}\n", .{@typeName(T)});
            return error.UnsupportedType;
        },
    };
}

pub fn calculateCompactSize(value: u128) usize {
    if (value < 64) {
        return 1;
    } else if (value < 16384) {
        return 2;
    } else if (value < 1073741824) {
        return 4;
    } else {
        var bytes: usize = 0;
        var v = value;
        while (v > 0) : (v /= 256) {
            bytes += 1;
        }
        return bytes + 1;
    }
}
