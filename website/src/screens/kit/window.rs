use damask::Component;

use crate::screens::palette::Palette;

/// The SVG document: the window's ground and the accent glow the app shell
/// paints from its top-left corner. Everything else is the default slot.
#[derive(Component)]
pub struct Window<'a> {
    pub p: &'a Palette,
    pub w: f64,
    pub h: f64,
}

impl Window<'_> {
    fn glow(&self) -> String {
        self.p.a("accent", 0.05)
    }

    fn glow_end(&self) -> String {
        self.p.a("accent", 0.0)
    }
}
