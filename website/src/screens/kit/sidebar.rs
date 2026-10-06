use damask::Component;

use crate::screens::demo;
use crate::screens::palette::{Palette, hex_alpha};

pub const WIDTH: f64 = 248.0;
const FOOTER: f64 = 28.0;

/// The translucent sidebar: connection card, filter, and the Pinned /
/// Queries / Schemas sections, laid out top-down from `y`.
#[derive(Component)]
pub struct Sidebar<'a> {
    pub p: &'a Palette,
    pub y: f64,
    pub h: f64,
    /// The table whose row is lit.
    pub active: Option<&'static str>,
}

pub enum Item {
    Section { label: &'static str, count: usize, y: f64 },
    Table { name: &'static str, stat: Option<&'static str>, indent: f64, y: f64, active: bool },
    Query { name: &'static str, ago: &'static str, y: f64 },
    Schema { name: &'static str, count: usize, open: bool, y: f64 },
    Folder { label: &'static str, count: usize, open: bool, y: f64 },
}

impl Sidebar<'_> {
    fn tint(&self, alpha: f64) -> String {
        hex_alpha(demo::CONN_TINT, alpha)
    }

    fn bottom(&self) -> f64 {
        self.y + self.h
    }

    fn footer_y(&self) -> f64 {
        self.bottom() - FOOTER
    }

    fn items(&self) -> Vec<Item> {
        let mut y = self.y + 98.0;
        let mut items = Vec::new();
        let section = |items: &mut Vec<Item>, y: &mut f64, label, count| {
            items.push(Item::Section { label, count, y: *y + 14.0 });
            *y += 14.0 + 12.0 + 6.0 + 2.0;
        };
        let active = |name: &str| self.active == Some(name);

        section(&mut items, &mut y, "Pinned", demo::PINNED.len());
        for name in demo::PINNED {
            items.push(Item::Table { name, stat: None, indent: 0.0, y, active: active(name) });
            y += 24.0;
        }
        y += 14.0;
        section(&mut items, &mut y, "Queries", demo::QUERIES.len());
        for (name, ago) in demo::QUERIES {
            items.push(Item::Query { name, ago, y });
            y += 24.0;
        }
        y += 14.0;
        section(&mut items, &mut y, "Schemas", 2);
        items.push(Item::Schema { name: "public", count: 15, open: true, y });
        y += 26.0;
        items.push(Item::Folder { label: "tables", count: demo::TABLES.len(), open: true, y });
        y += 24.0;
        for t in &demo::TABLES {
            items.push(Item::Table { name: t.name, stat: Some(t.rows), indent: 2.0, y, active: false });
            y += 24.0;
        }
        items.push(Item::Folder { label: "views", count: 3, open: false, y });
        y += 24.0;
        items.push(Item::Schema { name: "analytics", count: 6, open: false, y });
        items
    }
}
