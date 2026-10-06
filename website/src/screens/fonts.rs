//! The app's bundled fonts: handed to resvg to draw with, and measured here so
//! a layout can size a pill to its label the way Flutter's would.

use std::sync::OnceLock;

use resvg::usvg::fontdb;

const FONT_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../assets/fonts");

pub const UI: &str = "Inter";
pub const MONO: &str = "JetBrains Mono";
pub const ICONS: &str = "Hugeicons Stroke Rounded";

pub fn database() -> fontdb::Database {
    let mut db = fontdb::Database::new();
    db.load_fonts_dir(FONT_DIR);
    db
}

/// The advance width of `text`, in px, ignoring kerning.
pub fn width(family: &str, weight: u16, size: f64, letter_spacing: f64, text: &str) -> f64 {
    static DB: OnceLock<fontdb::Database> = OnceLock::new();
    let db = DB.get_or_init(database);
    let query = fontdb::Query {
        families: &[fontdb::Family::Name(family)],
        weight: fontdb::Weight(weight),
        ..Default::default()
    };
    let id = db.query(&query).unwrap_or_else(|| panic!("font {family} {weight} is bundled"));
    db.with_face_data(id, |data, index| {
        let face = ttf_parser::Face::parse(data, index).expect("parsable font");
        let scale = size / face.units_per_em() as f64;
        text.chars()
            .map(|c| {
                let advance = face.glyph_index(c).and_then(|g| face.glyph_hor_advance(g)).unwrap_or(0);
                advance as f64 * scale + letter_spacing
            })
            .sum()
    })
    .expect("font data")
}

pub fn ui(weight: u16, size: f64, text: &str) -> f64 {
    width(UI, weight, size, 0.0, text)
}

pub fn mono(size: f64, text: &str) -> f64 {
    width(MONO, 400, size, 0.0, text)
}
