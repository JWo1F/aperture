use damask::Component;

/// The app's painted table icon: a rounded frame with a tinted header band
/// and one row divider.
#[derive(Component)]
pub struct TableGlyph {
    pub cx: f64,
    pub cy: f64,
    pub size: f64,
    pub color: String,
}

impl TableGlyph {
    fn x(&self) -> f64 {
        self.cx - self.size / 2.0 + 0.6
    }

    fn y(&self) -> f64 {
        self.cy - self.size / 2.0 + 0.6
    }

    fn side(&self) -> f64 {
        self.size - 1.2
    }

    fn band(&self) -> f64 {
        self.side() * 0.34
    }

    fn divider(&self) -> f64 {
        self.y() + self.band() + (self.side() - self.band()) / 2.0
    }
}
