//! Hugeicons glyphs by slug, read from the app's generated icon table so the
//! screenshots draw exactly the glyphs the app does.

use std::collections::HashMap;
use std::sync::OnceLock;

const HUGEICONS: &str = include_str!("../../../lib/theme/hugeicons.dart");

pub fn glyph(slug: &str) -> char {
    static TABLE: OnceLock<HashMap<&'static str, char>> = OnceLock::new();
    let table = TABLE.get_or_init(|| {
        let mut table = HashMap::new();
        let mut pending = None;
        for line in HUGEICONS.lines().map(str::trim) {
            if let Some(slug) = line.strip_prefix("/// `").and_then(|s| s.strip_suffix('`')) {
                pending = Some(slug);
            } else if let (Some(slug), Some(at)) = (pending, line.find("IconData(0x")) {
                let hex = &line[at + 11..];
                let hex = &hex[..hex.find(',').expect("IconData(0x…, …)")];
                let code = u32::from_str_radix(hex, 16).expect("codepoint");
                table.insert(slug, char::from_u32(code).expect("valid codepoint"));
                pending = None;
            }
        }
        table
    });
    *table.get(slug).unwrap_or_else(|| panic!("no Hugeicons glyph `{slug}`"))
}

#[cfg(test)]
mod tests {
    #[test]
    fn slugs_resolve_to_the_apps_codepoints() {
        assert_eq!(super::glyph("database-01") as u32, 0xf1b20);
        assert_eq!(super::glyph("arrow-up-right-01") as u32, 0xf1640);
    }
}
