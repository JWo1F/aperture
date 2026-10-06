use damask::Component;

use crate::screens::demo;
use crate::screens::palette::Palette;
use crate::screens::{H, W};

/// The hero: `orders`, filtered and sorted, with three staged changes.
#[derive(Component)]
pub struct TableShot<'a> {
    pub p: &'a Palette,
}

impl TableShot<'_> {
    fn size(&self) -> (f64, f64) {
        (W, H)
    }

    fn data(&self) -> demo::GridData {
        demo::orders()
    }
}
