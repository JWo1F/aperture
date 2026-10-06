use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Section {
    Results,
    Plan,
    Messages,
}

/// The strip under the editor's split: RESULTS · PLAN · MESSAGES.
#[derive(Component)]
pub struct SectionStrip<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub active: Section,
    pub counts: [Option<&'static str>; 3],
}

pub struct Item {
    pub section: Section,
    pub label: &'static str,
    pub icon: Option<&'static str>,
    pub count: Option<&'static str>,
    pub x: f64,
    pub w: f64,
}

impl SectionStrip<'_> {
    fn items(&self) -> Vec<Item> {
        let mut x = self.x + 6.0;
        [
            (Section::Results, "RESULTS", None),
            (Section::Plan, "PLAN", Some("hierarchy")),
            (Section::Messages, "MESSAGES", Some("message-01")),
        ]
        .into_iter()
        .zip(self.counts)
        .map(|((section, label, icon), count)| {
            let count_w = count.map_or(0.0, |c| 6.0 + fonts::mono(9.5, c));
            let w = 10.0 + 11.0 + 6.0 + fonts::width(fonts::MONO, 600, 10.0, 0.6, label) + count_w + 10.0;
            let item = Item { section, label, icon, count, x, w };
            x += w;
            item
        })
        .collect()
    }
}
