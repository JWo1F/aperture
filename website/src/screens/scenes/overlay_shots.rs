//! The table view with something open on top of it.

use damask::Component;

use crate::screens::demo;
use crate::screens::palette::Palette;

/// Editing `placed_at` in the timestamptz picker.
#[derive(Component)]
#[template(path = "picker_shot.dmk")]
pub struct PickerShot<'a> {
    pub p: &'a Palette,
}

/// ⌘K, searching.
#[derive(Component)]
#[template(path = "palette_shot.dmk")]
pub struct PaletteShot<'a> {
    pub p: &'a Palette,
}

/// The pending-edits review before Apply.
#[derive(Component)]
#[template(path = "edits_shot.dmk")]
pub struct EditsShot<'a> {
    pub p: &'a Palette,
}

pub fn data() -> demo::GridData {
    demo::orders()
}
