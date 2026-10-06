use damask::Component;

use crate::screens::palette::Palette;

pub const LINE: f64 = 18.1;
pub const PAD: f64 = 12.0;

/// The multi-line SQL editor: gutter with line numbers and per-statement run
/// icons, the caret statement's band, and highlighted code.
#[derive(Component)]
pub struct SqlEditor<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub code: &'static str,
    /// Line ranges (inclusive) of each statement, comments included.
    pub statements: Vec<(usize, usize)>,
    /// Statement index holding the caret, and the caret's (line, column).
    pub caret: (usize, usize, usize),
}

impl SqlEditor<'_> {
    fn lines(&self) -> impl Iterator<Item = (usize, f64, &'static str)> {
        let top = self.y + PAD;
        self.code.lines().enumerate().map(move |(i, line)| (i, top + i as f64 * LINE + LINE / 2.0, line))
    }

    fn numbers_right(&self) -> f64 {
        self.x + 30.0
    }

    fn icon_x(&self) -> f64 {
        self.x + 45.0
    }

    fn divider(&self) -> f64 {
        self.x + 55.0
    }

    fn code_x(&self) -> f64 {
        self.x + 66.0
    }

    /// The first line of a statement that is not a comment: where its ▶ sits.
    fn run_lines(&self) -> Vec<usize> {
        let lines: Vec<&str> = self.code.lines().collect();
        self.statements
            .iter()
            .map(|(start, end)| (*start..=*end).find(|i| !lines[*i].trim_start().starts_with("--")).unwrap_or(*start))
            .collect()
    }

    fn band(&self) -> (f64, f64) {
        let (start, end) = self.statements[self.caret.0];
        let top = self.y + PAD + start as f64 * LINE;
        (top, (end - start + 1) as f64 * LINE)
    }

    fn caret_xy(&self) -> (f64, f64) {
        let (_, line, column) = self.caret;
        (self.code_x() + column as f64 * 12.5 * 0.6, self.y + PAD + line as f64 * LINE)
    }
}
