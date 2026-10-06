use damask::Component;

use crate::screens::{fonts, icons};

/// A Hugeicons glyph centred on (`cx`, `cy`).
#[derive(Component)]
pub struct Glyph {
    pub slug: &'static str,
    pub cx: f64,
    pub cy: f64,
    pub size: f64,
    pub fill: String,
    pub rotate: Option<f64>,
}

impl Glyph {
    fn ch(&self) -> String {
        icons::glyph(self.slug).to_string()
    }

    fn family(&self) -> &'static str {
        fonts::ICONS
    }

    fn baseline(&self) -> f64 {
        self.cy + self.size * 0.5 - self.size * 0.07
    }

    fn transform(&self) -> Option<String> {
        self.rotate.map(|deg| format!("rotate({deg} {} {})", self.cx, self.cy))
    }
}
