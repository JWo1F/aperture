use damask::Component;

use crate::screens::demo::{ColKind, GridData, RowState, Value};
use crate::screens::palette::Palette;

pub const HEADER: f64 = 28.0;
pub const ROW: f64 = 26.0;
pub const INDEX: f64 = 64.0;
const CELL_FONT: f64 = 11.5;

/// The results grid: index column, typed header, type-coloured cells, and
/// the staged-change paint (edited cell, inserted and deleted rows).
#[derive(Component)]
pub struct Grid<'a> {
    pub p: &'a Palette,
    /// Unique within the document — names the clip path.
    pub id: &'static str,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub data: &'a GridData,
}

pub struct Cell {
    pub x: f64,
    pub w: f64,
    pub text: String,
    pub color: String,
    pub weight: Option<u16>,
    pub italic: Option<bool>,
    pub json: bool,
    pub edited: bool,
    pub focused: bool,
}

pub struct RowView {
    pub y: f64,
    pub state: RowState,
    pub label: String,
    pub cells: Vec<Cell>,
}

/// Clips `text` to what fits in `width` px of JetBrains Mono at `size`, with
/// an ellipsis — every glyph of the face is 0.6 em wide.
pub fn ellipsize(text: &str, width: f64, size: f64) -> String {
    let fits = (width / (size * 0.6)).floor() as usize;
    if text.chars().count() <= fits {
        text.to_string()
    } else {
        let mut cut: String = text.chars().take(fits.saturating_sub(1)).collect();
        cut.push('…');
        cut
    }
}

impl Grid<'_> {
    fn clip(&self) -> String {
        format!("url(#{})", self.id)
    }

    fn columns(&self) -> impl Iterator<Item = (f64, &crate::screens::demo::Column)> {
        let mut x = self.x + INDEX;
        self.data.columns.iter().map(move |c| {
            let at = x;
            x += c.width;
            (at, c)
        })
    }

    fn rows(&self) -> Vec<RowView> {
        let p = self.p;
        self.data
            .rows
            .iter()
            .enumerate()
            .map(|(r, row)| {
                let cells = self
                    .columns()
                    .zip(&row.cells)
                    .enumerate()
                    .map(|(c, ((x, col), value))| {
                        let (raw, color, weight, italic) = match value {
                            Value::Num(s) => (s.clone(), p.c("tNum"), None, None),
                            Value::Str(s) => (s.clone(), p.c("tStr"), None, None),
                            Value::Bool(true) => ("true".into(), p.c("tBool"), None, None),
                            Value::Bool(false) => ("false".into(), p.c("textMuted"), None, None),
                            Value::Date(s) => (s.clone(), p.c("tDate"), None, None),
                            Value::Json(s) => (s.clone(), p.c("tJson"), None, None),
                            Value::Uuid(s) => (s.clone(), p.c("tUuid"), None, None),
                            Value::Null => ("NULL".into(), p.c("textMuted"), None, Some(true)),
                            Value::Default => ("DEFAULT".into(), p.c("accent"), Some(600), None),
                        };
                        let edited = row.edited.contains(&c);
                        Cell {
                            x,
                            w: col.width,
                            text: ellipsize(&raw, col.width - 18.0, CELL_FONT),
                            color: if edited { p.c("textPrimary") } else { color },
                            weight,
                            italic,
                            json: matches!(value, Value::Json(_)),
                            edited,
                            focused: self.data.focus == Some((r, c)),
                        }
                    })
                    .collect();
                RowView { y: self.y + HEADER + r as f64 * ROW, state: row.state, label: row.label.clone(), cells }
            })
            .filter(|row| row.y < self.y + self.h)
            .collect()
    }

    fn row_tint(&self, state: RowState) -> Option<String> {
        match state {
            RowState::Normal => None,
            RowState::Selected => Some(self.p.c("gridRowSelection")),
            RowState::Inserted => Some(self.p.c("gridRowInsert")),
            RowState::Deleted => Some(self.p.c("gridRowDelete")),
        }
    }

    fn stripe(&self, state: RowState) -> Option<String> {
        match state {
            RowState::Inserted => Some(self.p.c("accent")),
            RowState::Deleted => Some(self.p.c("error")),
            _ => None,
        }
    }

    fn index_ink(&self, state: RowState) -> (String, u16) {
        match state {
            RowState::Normal => (self.p.c("text4"), 400),
            RowState::Selected | RowState::Inserted => (self.p.c("accent"), 600),
            RowState::Deleted => (self.p.c("error"), 600),
        }
    }

    fn header_ink(&self, kind: ColKind) -> String {
        match kind {
            ColKind::Plain => self.p.c("textPrimary"),
            ColKind::Pk => self.p.c("accent"),
            ColKind::Fk => self.p.c("tFk"),
        }
    }

    fn body_bottom(&self) -> f64 {
        self.y + self.h
    }

    fn content_w(&self) -> f64 {
        INDEX + self.data.columns.iter().map(|c| c.width).sum::<f64>()
    }

    /// The scroll thumbs, sized as if the page held four screens of columns
    /// and two of rows.
    fn v_thumb(&self) -> (f64, f64) {
        let track = self.h - HEADER - 8.0;
        (self.y + HEADER + 4.0 + track * 0.08, track * 0.42)
    }

    fn h_thumb(&self) -> (f64, f64) {
        let visible = (self.w / self.content_w()).min(1.0);
        (self.x + INDEX + 4.0, (self.w - INDEX - 12.0) * visible)
    }
}
