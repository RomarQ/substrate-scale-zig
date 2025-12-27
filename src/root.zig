pub const encoder = @import("encoder.zig");
pub const decoder = @import("decoder.zig");
pub const types = @import("types.zig");

// Re-export common types for convenience
pub const Compact = types.Compact;
pub const Result = types.Result;
pub const Option = types.Option;

// Include tests
comptime {
    _ = @import("tests.zig");
}
