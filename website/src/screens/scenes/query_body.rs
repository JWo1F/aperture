use damask::Component;

use crate::screens::demo::GridData;
use crate::screens::kit::{Advice, Node, Section, sql_editor};
use crate::screens::palette::Palette;
use crate::screens::{H, W};

pub enum Bottom<'a> {
    Results(&'a GridData),
    Plan(Vec<Advice>, Vec<Node>),
}

/// A query tab: the editor above the split, a section below it.
#[derive(Component)]
pub struct QueryBody<'a> {
    pub p: &'a Palette,
    pub tab: &'static str,
    pub sql: &'static str,
    pub statements: Vec<(usize, usize)>,
    pub caret: (usize, usize, usize),
    pub position: &'static str,
    pub bottom: Bottom<'a>,
}

impl QueryBody<'_> {
    fn x(&self) -> f64 {
        crate::screens::kit::sidebar::WIDTH
    }

    fn w(&self) -> f64 {
        W - self.x()
    }

    fn win_w(&self) -> f64 {
        W
    }

    fn win_h(&self) -> f64 {
        H
    }

    fn editor_y(&self) -> f64 {
        36.0 + 36.0 + 34.0
    }

    fn editor_h(&self) -> f64 {
        self.sql.lines().count() as f64 * sql_editor::LINE + sql_editor::PAD * 2.0 + 6.0
    }

    fn strip_y(&self) -> f64 {
        self.editor_y() + self.editor_h() + 6.0
    }

    fn section_y(&self) -> f64 {
        self.strip_y() + 26.0
    }

    fn section_h(&self) -> f64 {
        H - 28.0 - self.section_y()
    }

    fn section(&self) -> Section {
        match self.bottom {
            Bottom::Results(_) => Section::Results,
            Bottom::Plan(..) => Section::Plan,
        }
    }

    fn counts(&self) -> [Option<&'static str>; 3] {
        match self.bottom {
            Bottom::Results(_) => [Some("10"), None, Some("2")],
            Bottom::Plan(..) => [None, Some("5"), Some("1")],
        }
    }

    fn stats(&self) -> Vec<(&'static str, &'static str)> {
        match self.bottom {
            Bottom::Results(_) => vec![("10", "rows"), ("38", "ms"), ("", "refreshed 14:02:11")],
            Bottom::Plan(..) => vec![("5", "nodes"), ("12.48", "ms"), ("", "explained 14:06:52")],
        }
    }

    fn kind(&self) -> &'static str {
        match self.bottom {
            Bottom::Results(_) => "SELECT",
            Bottom::Plan(..) => "EXPLAIN",
        }
    }
}
