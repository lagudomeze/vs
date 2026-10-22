//! Standalone entry for `zig build test-qa`: the module root is src/ so the
//! QA harness may import both game/ and core/ through their relative paths.
test {
    _ = @import("qa2/tome_regression.zig");
}
