use damask::Component;

use crate::screens::palette::Palette;

pub struct Clause {
    pub label: &'static str,
    /// The typed SQL, or `None` for the hint.
    pub code: Option<&'static str>,
    pub hint: &'static str,
    pub icon: &'static str,
}

/// The table view's three single-line clause fields: WHERE, SELECT, ORDER.
#[derive(Component)]
pub struct ClauseBar<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub clauses: Vec<Clause>,
}

impl ClauseBar<'_> {
    fn rows(&self) -> impl Iterator<Item = (f64, &Clause)> {
        self.clauses.iter().enumerate().map(|(i, c)| (self.y + i as f64 * 26.0, c))
    }
}
