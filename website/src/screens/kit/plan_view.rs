use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

/// A warning from the rule pass.
pub struct Advice {
    pub title: &'static str,
    pub body: &'static str,
}

pub struct Node {
    pub depth: usize,
    pub op: &'static str,
    pub target: &'static str,
    pub ms: f64,
    pub pct: u32,
    pub desc: &'static str,
    pub chips: &'static [(&'static str, &'static str)],
    pub rows: &'static str,
    pub estimated: &'static str,
    pub off: bool,
    pub slowest: bool,
}

/// The EXPLAIN view: timing summary, advice cards, and the node tree as
/// indented cards with a time bar each.
#[derive(Component)]
pub struct PlanView<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub advice: &'a [Advice],
    pub nodes: &'a [Node],
}

pub struct Placed<'n> {
    pub node: &'n Node,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

const PAD: f64 = 12.0;
const SUMMARY_H: f64 = 74.0;
const ADVICE_H: f64 = 52.0;
const INDENT: f64 = 22.0;

impl PlanView<'_> {
    fn inner_x(&self) -> f64 {
        self.x + PAD
    }

    fn inner_w(&self) -> f64 {
        self.w - PAD * 2.0
    }

    fn summary_y(&self) -> f64 {
        self.y + PAD
    }

    fn advice_at(&self) -> Vec<(f64, &Advice)> {
        let mut y = self.summary_y() + SUMMARY_H + 10.0;
        self.advice
            .iter()
            .map(|a| {
                let at = y;
                y += ADVICE_H + 6.0;
                (at, a)
            })
            .collect()
    }

    fn placed(&self) -> Vec<Placed<'_>> {
        let mut y = self.summary_y() + SUMMARY_H + 10.0 + self.advice.len() as f64 * (ADVICE_H + 6.0) + 4.0;
        self.nodes
            .iter()
            .map(|node| {
                let x = self.inner_x() + node.depth as f64 * INDENT;
                let h = if node.chips.is_empty() { 92.0 } else { 119.0 };
                let placed = Placed { node, x, y, w: self.inner_x() + self.inner_w() - x, h };
                y += h + 6.0;
                placed
            })
            .collect()
    }

    pub fn badge_color(op: &str) -> &'static str {
        let op = op.to_ascii_lowercase();
        if op.contains("join") || op.contains("hash") {
            "accent"
        } else if op.contains("scan") {
            "sqlKeyword"
        } else if op.contains("aggregate") || op.contains("group") {
            "sqlFunction"
        } else if op.contains("sort") || op.contains("limit") {
            "sqlString"
        } else {
            "textSecondary"
        }
    }

    fn badge_w(op: &str) -> f64 {
        fonts::width(fonts::MONO, 600, 12.0, 0.0, op) + 14.0
    }

    fn pct_color(node: &Node) -> &'static str {
        if node.pct >= 60 || node.slowest {
            "warning"
        } else if node.pct >= 25 {
            "accent"
        } else {
            "textMuted"
        }
    }

    fn bar_fill(&self, node: &Node) -> String {
        if node.pct >= 60 || node.slowest {
            self.p.c("warning")
        } else if node.pct >= 25 {
            self.p.c("accent")
        } else {
            self.p.a("accent", 0.55)
        }
    }

    fn chip_w(label: &str, value: &str) -> f64 {
        fonts::mono(10.5, label) + fonts::mono(10.5, " ") + fonts::mono(10.5, value) + 12.0
    }

    fn chips(&self, placed: &Placed) -> Vec<(f64, &'static str, &'static str)> {
        let mut x = placed.x + 12.0;
        placed
            .node
            .chips
            .iter()
            .map(|(label, value)| {
                let at = x;
                x += Self::chip_w(label, value) + 6.0;
                (at, *label, *value)
            })
            .collect()
    }

    fn mono_w(size: f64, text: &str) -> f64 {
        fonts::mono(size, text)
    }

    fn bold_w(size: f64, text: &str) -> f64 {
        fonts::width(fonts::MONO, 600, size, 0.0, text)
    }

    fn clip_h(&self) -> f64 {
        self.h
    }
}
