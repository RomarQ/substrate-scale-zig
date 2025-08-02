pub const encoder = @import("encoder.zig");
pub const decoder = @import("decoder.zig");

// Include tests
comptime {
    _ = @import("tests.zig");
}
