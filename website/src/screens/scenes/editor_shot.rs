use damask::Component;

use crate::screens::demo;
use crate::screens::palette::Palette;

/// A two-statement script with the caret in the first, and its results.
#[derive(Component)]
pub struct EditorShot<'a> {
    pub p: &'a Palette,
}

impl EditorShot<'_> {
    fn data(&self) -> demo::GridData {
        demo::revenue()
    }
}
