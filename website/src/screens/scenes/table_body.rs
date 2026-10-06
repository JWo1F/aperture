use damask::Component;

use crate::screens::demo::GridData;
use crate::screens::kit::{Clause, Page, Tab, TabKind};
use crate::screens::palette::Palette;
use crate::screens::{H, W};

/// The app with `orders` open: toolbar, sidebar, tabs, clause bar, grid and
/// pagebar. Overlay scenes draw on top of it.
#[derive(Component)]
pub struct TableBody<'a> {
    pub p: &'a Palette,
    pub data: &'a GridData,
}

pub fn tabs(active: &str) -> Vec<Tab> {
    [
        ("orders", TabKind::Table, true),
        ("customers", TabKind::Table, false),
        ("Revenue by month", TabKind::Query, false),
        ("orders", TabKind::Schema, false),
    ]
    .into_iter()
    .enumerate()
    .map(|(i, (label, kind, dirty))| Tab { label, kind, active: tab_key(i, label) == active, dirty })
    .collect()
}

fn tab_key(i: usize, label: &str) -> String {
    if i == 3 { format!("{label} ddl") } else { label.to_string() }
}

impl TableBody<'_> {
    fn w(&self) -> f64 {
        W
    }

    fn h(&self) -> f64 {
        H
    }

    fn work_x(&self) -> f64 {
        crate::screens::kit::sidebar::WIDTH
    }

    fn work_w(&self) -> f64 {
        W - self.work_x()
    }

    fn grid_y(&self) -> f64 {
        36.0 + 36.0 + 78.0
    }

    fn grid_h(&self) -> f64 {
        H - self.grid_y() - 28.0
    }

    fn clauses(&self) -> Vec<Clause> {
        vec![
            Clause {
                label: "WHERE",
                code: Some("status in ('paid', 'shipped') and total > 25"),
                hint: "",
                icon: "filter",
            },
            Clause { label: "SELECT", code: None, hint: "*  or  col_a, col_b", icon: "column-insert" },
            Clause { label: "ORDER", code: Some("placed_at desc"), hint: "", icon: "sorting-01" },
        ]
    }

    fn pages(&self) -> Vec<Page> {
        let mut pages = vec![Page::Number(1, false), Page::Gap];
        pages.extend((5..=11).map(|n| Page::Number(n, n == 8)));
        pages.extend([Page::Gap, Page::Number(965, false)]);
        pages
    }

    fn stats(&self) -> Vec<(&'static str, &'static str)> {
        vec![("50", "rows"), ("48,213", "total"), ("14", "ms"), ("", "refreshed 14:02:11")]
    }

    fn tabs(&self) -> Vec<Tab> {
        tabs("orders")
    }
}
