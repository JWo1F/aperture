use damask::Component;

use super::KbdChip;
use crate::screens::fonts;
use crate::screens::palette::Palette;

pub const HEIGHT: f64 = 34.0;

/// The query tab's toolbar: Run, Run all, Explain, the statement readout.
#[derive(Component)]
pub struct QueryToolbar<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    /// `"1/2"` — which statement the caret is in.
    pub position: &'static str,
    pub kind: &'static str,
}

pub struct Ghost {
    pub x: f64,
    pub w: f64,
    pub icon: &'static str,
    pub label: &'static str,
    pub keys: &'static [&'static str],
}

impl QueryToolbar<'_> {
    fn cy(&self) -> f64 {
        self.y + HEIGHT / 2.0
    }

    fn keys_w(keys: &[&str], size: f64) -> f64 {
        keys.iter().map(|k| KbdChip::width(k, size)).sum::<f64>() + 3.0 * (keys.len().saturating_sub(1)) as f64
    }

    fn run_w(&self) -> f64 {
        9.0 + 12.0 + 6.0 + fonts::ui(600, 11.5, "Run") + 8.0 + Self::keys_w(&["⌘", "↵"], 9.5) + 6.0
    }

    fn ghosts(&self) -> Vec<Ghost> {
        let mut x = self.x + 8.0 + self.run_w() + 5.0;
        let mut ghosts = Vec::new();
        for (icon, label, keys) in [("flash", "Run all", &["⌘", "⇧", "↵"][..]), ("hierarchy", "Explain", &[][..])]
        {
            let keys_w = if keys.is_empty() { 3.0 } else { 7.0 + Self::keys_w(keys, 10.0) + 6.0 };
            let w = 9.0 + 12.0 + 5.0 + fonts::ui(500, 11.5, label) + keys_w;
            ghosts.push(Ghost { x, w, icon, label, keys });
            x += w + if label == "Run all" { 21.0 } else { 5.0 };
        }
        ghosts
    }

    fn rail_x(&self) -> f64 {
        let first = &self.ghosts()[0];
        first.x + first.w + 10.0
    }

    fn chips(&self, x: f64, keys: &'static [&'static str], size: f64) -> Vec<(f64, &'static str)> {
        let mut at = x;
        keys.iter()
            .map(|k| {
                let here = at;
                at += KbdChip::width(k, size) + 3.0;
                (here, *k)
            })
            .collect()
    }

    fn run_keys_x(&self) -> f64 {
        self.x + 8.0 + 9.0 + 12.0 + 6.0 + fonts::ui(600, 11.5, "Run") + 8.0
    }

    fn ghost_keys_x(g: &Ghost) -> f64 {
        g.x + 9.0 + 12.0 + 5.0 + fonts::ui(500, 11.5, g.label) + 7.0
    }

    fn readout_x(&self) -> f64 {
        self.x + self.w / 2.0 + 60.0
    }
}
