use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum TabKind {
    Table,
    Query,
    Schema,
}

pub struct Tab {
    pub label: &'static str,
    pub kind: TabKind,
    pub active: bool,
    /// Staged edits: the dot becomes a warn ring.
    pub dirty: bool,
}

/// The workspace's tab strip: lifted pills, a type-coloured status dot each.
#[derive(Component)]
pub struct TabStrip<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub tabs: Vec<Tab>,
}

pub struct Placed<'t> {
    pub tab: &'t Tab,
    pub x: f64,
    pub w: f64,
}

impl TabStrip<'_> {
    fn label_size() -> f64 {
        12.5
    }

    fn placed(&self) -> Vec<Placed<'_>> {
        let mut x = self.x + 6.0 + 2.0;
        self.tabs
            .iter()
            .map(|tab| {
                let label = fonts::width(fonts::UI, 500, Self::label_size(), -0.2, tab.label);
                let suffix = if tab.kind == TabKind::Schema { fonts::ui(500, 12.5, "  ddl") } else { 0.0 };
                let w = (10.0 + 14.0 + 9.0 + label + suffix + 6.0 + 16.0 + 4.0).min(220.0);
                let placed = Placed { tab, x, w };
                x += w + 4.0;
                placed
            })
            .collect()
    }

    fn plus_x(&self) -> f64 {
        self.placed().last().map_or(self.x + 8.0, |t| t.x + t.w + 4.0) + 11.0
    }

    fn dot(&self, kind: TabKind) -> &'static str {
        match kind {
            TabKind::Table => "success",
            TabKind::Query => "accent",
            TabKind::Schema => "tDate",
        }
    }
}
