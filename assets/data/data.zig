//! Raw embedded content data for src/game/content.zig.
//!
//! The JSON files live next to the other asset sources, but Zig refuses
//! `@embedFile` paths outside the importing module's package path, so this
//! tiny module is registered as the anonymous `data` import in build.zig.
//! content.zig owns parsing, validation and the built-in fallbacks.

pub const items_json = @embedFile("items.json");
pub const enemies_json = @embedFile("enemies.json");
pub const skills_json = @embedFile("skills.json");
