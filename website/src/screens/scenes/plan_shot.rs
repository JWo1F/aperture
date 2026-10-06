use damask::Component;

use crate::screens::palette::Palette;

/// EXPLAIN ANALYZE of a join, with advice and the node tree.
#[derive(Component)]
pub struct PlanShot<'a> {
    pub p: &'a Palette,
}
