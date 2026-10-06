use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

pub const WIDTH: f64 = 348.0;
pub const HEIGHT: f64 = 346.0;

/// The timestamptz picker anchored to a cell: segmented value line, quick
/// actions, calendar, and the NULL / Default / Revert / Save footer.
#[derive(Component)]
pub struct CellPicker<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
}

pub struct Segment {
    pub x: f64,
    pub w: f64,
    pub text: &'static str,
    pub editing: bool,
}

pub struct Day {
    pub x: f64,
    pub y: f64,
    pub n: u32,
    pub in_month: bool,
    pub selected: bool,
    pub today: bool,
}

const VALUE_Y: f64 = 30.0;
const QUICK_Y: f64 = 66.0;
const CAL_Y: f64 = 98.0;
const FOOTER_Y: f64 = HEIGHT - 38.0;

impl CellPicker<'_> {
    fn w(&self) -> f64 {
        WIDTH
    }

    fn h(&self) -> f64 {
        HEIGHT
    }

    fn value_cy(&self) -> f64 {
        self.y + VALUE_Y + 8.0 + 12.0
    }

    /// YYYY-MM-DD  HH:MM:SS, with the hour mid-edit.
    fn segments(&self) -> (Vec<Segment>, Vec<(f64, &'static str)>) {
        let punct = fonts::mono(14.0, "-");
        let mut x = self.x + 10.0;
        let mut segments = Vec::new();
        let mut marks = Vec::new();
        let parts: [(&'static str, f64, Option<&'static str>); 6] = [
            ("2026", 44.0, Some("-")),
            ("10", 26.0, Some("-")),
            ("04", 26.0, None),
            ("13", 26.0, Some(":")),
            ("25", 26.0, Some(":")),
            ("43", 26.0, None),
        ];
        for (i, (text, w, after)) in parts.into_iter().enumerate() {
            segments.push(Segment { x, w, text, editing: i == 3 });
            x += w;
            if let Some(mark) = after {
                marks.push((x + punct / 2.0, mark));
                x += punct;
            } else if i == 2 {
                x += 12.0;
            }
        }
        (segments, marks)
    }

    fn tz_x(&self) -> f64 {
        self.x + WIDTH - 10.0 - 88.0
    }

    fn quick_cy(&self) -> f64 {
        self.y + QUICK_Y + 16.0
    }

    fn quick(&self) -> Vec<(f64, f64, Option<&'static str>, &'static str, bool)> {
        let mut x = self.x + 8.0;
        [(Some("flash"), "Now", true), (None, "Today 00:00", false), (None, "Tomorrow", false)]
            .into_iter()
            .map(|(icon, label, primary)| {
                let w = 7.0 + icon.map_or(0.0, |_| 15.0) + fonts::ui(500, 11.5, label) + 7.0;
                let chip = (x, w, icon, label, primary);
                x += w + 2.0;
                chip
            })
            .collect()
    }

    fn cal_header_cy(&self) -> f64 {
        self.y + CAL_Y + 15.0
    }

    fn dow_cy(&self) -> f64 {
        self.y + CAL_Y + 30.0 + 9.0
    }

    fn cell_w(&self) -> f64 {
        (WIDTH - 16.0) / 7.0
    }

    fn dow(&self) -> impl Iterator<Item = (f64, &'static str)> + '_ {
        ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
            .into_iter()
            .enumerate()
            .map(|(i, d)| (self.x + 8.0 + self.cell_w() * (i as f64 + 0.5), d))
    }

    /// October 2026 opens on a Thursday; the grid starts on Sunday the 27th.
    fn days(&self) -> Vec<Day> {
        let top = self.y + CAL_Y + 48.0;
        (0..42)
            .map(|i| {
                let (n, in_month) = match i {
                    0..=3 => (27 + i, false),
                    4..=34 => (i - 3, true),
                    _ => (i - 34, false),
                };
                Day {
                    x: self.x + 8.0 + self.cell_w() * (i % 7) as f64,
                    y: top + (i / 7) as f64 * 26.0,
                    n,
                    in_month,
                    selected: in_month && n == 4,
                    today: in_month && n == 6,
                }
            })
            .collect()
    }

    fn footer_cy(&self) -> f64 {
        self.y + FOOTER_Y + 19.0
    }

    fn footer_actions(&self) -> Vec<(f64, &'static str)> {
        let mut x = self.x + 6.0 + 7.0;
        ["NULL", "Default", "Revert"]
            .into_iter()
            .map(|label| {
                let at = x;
                x += fonts::ui(500, 11.5, label) + 14.0;
                (at, label)
            })
            .collect()
    }

    fn save_w(&self) -> f64 {
        10.0 + fonts::ui(500, 11.5, "Save") + 6.0 + super::KbdChip::width("⌘↵", 9.5) + 4.0
    }
}
