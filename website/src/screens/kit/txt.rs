use damask::Component;

use crate::screens::fonts;

/// A line of text placed by the vertical centre of its box, the way a
/// Flutter `Row` centres it — SVG places by baseline, so this converts.
#[derive(Component)]
pub struct Txt {
    pub x: f64,
    /// Vertical centre of the line box.
    pub y: f64,
    pub size: f64,
    pub fill: String,
    pub weight: Option<u16>,
    pub mono: Option<bool>,
    pub italic: Option<bool>,
    pub spacing: Option<f64>,
    /// `start` (default), `middle` or `end`.
    pub anchor: Option<&'static str>,
    pub opacity: Option<f64>,
}

impl Txt {
    fn family(&self) -> &'static str {
        if self.mono.unwrap_or(false) { fonts::MONO } else { fonts::UI }
    }

    fn baseline(&self) -> f64 {
        self.y + self.size * 0.36
    }

    fn style(&self) -> Option<&'static str> {
        self.italic.unwrap_or(false).then_some("italic")
    }
}
