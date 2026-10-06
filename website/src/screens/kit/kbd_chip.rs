use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

/// A key cap. `on_accent` draws it white-on-translucent for use inside an
/// accent button, as the app's Run and Apply buttons do.
#[derive(Component)]
pub struct KbdChip<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub cy: f64,
    pub key: String,
    pub size: f64,
    pub on_accent: Option<bool>,
}

impl KbdChip<'_> {
    pub fn width(key: &str, size: f64) -> f64 {
        (fonts::mono(size, key) + 8.0).max(size + 6.0)
    }

    fn w(&self) -> f64 {
        Self::width(&self.key, self.size)
    }

    fn h(&self) -> f64 {
        self.size + 6.0
    }

    fn fill(&self) -> String {
        if self.on_accent.unwrap_or(false) { "rgba(255,255,255,0.16)".into() } else { self.p.c("surfaceAlt") }
    }

    fn stroke(&self) -> String {
        if self.on_accent.unwrap_or(false) { "none".into() } else { self.p.c("border") }
    }

    fn ink(&self) -> String {
        if self.on_accent.unwrap_or(false) { "rgba(255,255,255,0.92)".into() } else { self.p.c("textMuted") }
    }
}
