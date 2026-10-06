use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

pub enum Page {
    Number(u32, bool),
    Gap,
}

/// A view's bottom bar: counts and timing on the left, pages on the right.
#[derive(Component)]
pub struct Pagebar<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    /// (value, unit) pairs: `("50", "rows")`. An empty value is a bare word.
    pub stats: Vec<(&'static str, &'static str)>,
    pub pages: Vec<Page>,
    /// Right-aligned status in place of pages: (dot colour token, word).
    pub status: Option<(&'static str, &'static str)>,
}

pub enum Run {
    Value(f64, &'static str),
    Unit(f64, &'static str),
    Dot(f64),
}

impl Pagebar<'_> {
    fn runs(&self) -> Vec<Run> {
        let mut x = self.x + 12.0;
        let mut runs = Vec::new();
        for (i, (value, unit)) in self.stats.iter().enumerate() {
            if i > 0 {
                runs.push(Run::Dot(x + 8.0));
                x += 8.0 + fonts::mono(10.5, "·") + 8.0;
            }
            if !value.is_empty() {
                runs.push(Run::Value(x, value));
                x += fonts::mono(10.5, value) + fonts::mono(10.5, " ");
            }
            runs.push(Run::Unit(x, unit));
            x += fonts::mono(10.5, unit);
        }
        runs
    }

    /// Right-to-left: chevron, pages, chevron.
    fn page_slots(&self) -> (f64, Vec<(f64, &Page)>, f64) {
        let right = self.x + self.w - 6.0;
        let next = right - 11.0;
        let mut x = right - 22.0;
        let mut slots: Vec<(f64, &Page)> = self
            .pages
            .iter()
            .rev()
            .map(|page| {
                let w = match page {
                    Page::Number(n, _) => (fonts::mono(10.5, &n.to_string()) + 10.0).max(16.0),
                    Page::Gap => 14.0,
                };
                x -= w;
                (x + w / 2.0, page)
            })
            .collect();
        slots.reverse();
        (x - 11.0, slots, next)
    }
}
