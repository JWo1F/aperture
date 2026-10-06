use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

pub const WIDTH: f64 = 600.0;
const SEARCH_H: f64 = 50.0;
const ROW_H: f64 = 46.0;
const FOOTER_H: f64 = 32.0;

pub struct Hit {
    pub title: &'static str,
    /// Character indices of `title` the query matched.
    pub matched: &'static [usize],
    pub subtitle: &'static str,
    pub icon: Option<&'static str>,
    pub chip: &'static str,
    /// Palette token for the kind chip.
    pub chip_color: &'static str,
}

/// The ⌘K palette over a scrim, mid-search.
#[derive(Component)]
pub struct CommandPalette<'a> {
    pub p: &'a Palette,
    /// Window size, for the scrim and the (0, -0.5) alignment.
    pub win_w: f64,
    pub win_h: f64,
    pub query: &'static str,
    pub hits: Vec<Hit>,
}

impl CommandPalette<'_> {
    fn h(&self) -> f64 {
        SEARCH_H + 1.0 + 12.0 + self.hits.len() as f64 * (ROW_H + 2.0) + FOOTER_H
    }

    fn x(&self) -> f64 {
        (self.win_w - WIDTH) / 2.0
    }

    fn y(&self) -> f64 {
        (self.win_h - self.h()) * 0.25
    }

    fn w(&self) -> f64 {
        WIDTH
    }

    fn rows(&self) -> impl Iterator<Item = (usize, f64, &Hit)> {
        let top = self.y() + SEARCH_H + 1.0 + 6.0;
        self.hits.iter().enumerate().map(move |(i, hit)| (i, top + i as f64 * (ROW_H + 2.0) + 1.0, hit))
    }

    /// The title split into runs of matched / unmatched characters.
    fn runs(hit: &Hit) -> Vec<(String, bool)> {
        let mut runs: Vec<(String, bool)> = Vec::new();
        for (i, c) in hit.title.chars().enumerate() {
            let on = hit.matched.contains(&i);
            match runs.last_mut() {
                Some((text, was)) if *was == on => text.push(c),
                _ => runs.push((c.to_string(), on)),
            }
        }
        runs
    }

    fn chip_w(text: &str) -> f64 {
        fonts::width(fonts::MONO, 600, 9.5, 0.0, text) + 14.0
    }

    fn footer_y(&self) -> f64 {
        self.y() + self.h() - FOOTER_H
    }

    fn query_w(&self) -> f64 {
        fonts::width(fonts::UI, 400, 15.0, 0.0, self.query)
    }

    fn hints(&self) -> Vec<(f64, Vec<&'static str>, &'static str)> {
        let mut x = self.x() + WIDTH - 14.0;
        let mut out = Vec::new();
        for (keys, label) in [(vec!["esc"], "Close"), (vec!["↵"], "Open"), (vec!["↑", "↓"], "Navigate")] {
            let label_w = fonts::ui(400, 10.5, label);
            let keys_w: f64 = keys.iter().map(|k| super::KbdChip::width(k, 10.0) + 3.0).sum();
            x -= label_w + 5.0 + keys_w;
            out.push((x, keys, label));
            x -= 12.0;
        }
        out
    }
}
