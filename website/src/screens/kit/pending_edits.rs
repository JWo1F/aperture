use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

pub const WIDTH: f64 = 760.0;
pub const HEIGHT: f64 = 640.0;
const HEADER_H: f64 = 96.0;
const FOOTER_H: f64 = 54.0;
const CODE_LINE: f64 = 17.0;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Update,
    Delete,
    Insert,
}

impl Kind {
    pub fn word(self) -> &'static str {
        match self {
            Kind::Update => "UPDATE",
            Kind::Delete => "DELETE",
            Kind::Insert => "INSERT",
        }
    }

    pub fn color(self) -> &'static str {
        match self {
            Kind::Update => "accent",
            Kind::Delete => "error",
            Kind::Insert => "success",
        }
    }
}

pub struct Statement {
    pub kind: Kind,
    pub row: Option<&'static str>,
    pub sql: &'static str,
}

/// The review modal: every staged statement, highlighted, before Apply.
#[derive(Component)]
pub struct PendingEdits<'a> {
    pub p: &'a Palette,
    pub win_w: f64,
    pub win_h: f64,
    pub statements: Vec<Statement>,
}

pub struct Card<'s> {
    pub n: usize,
    pub statement: &'s Statement,
    pub y: f64,
    pub h: f64,
}

impl PendingEdits<'_> {
    fn x(&self) -> f64 {
        (self.win_w - WIDTH) / 2.0
    }

    fn y(&self) -> f64 {
        (self.win_h - HEIGHT) / 2.0
    }

    fn w(&self) -> f64 {
        WIDTH
    }

    fn h(&self) -> f64 {
        HEIGHT
    }

    fn cards(&self) -> Vec<Card<'_>> {
        let mut y = self.y() + HEADER_H + 18.0;
        self.statements
            .iter()
            .enumerate()
            .map(|(i, statement)| {
                let h = 38.0 + 1.0 + 21.0 + statement.sql.lines().count() as f64 * CODE_LINE;
                let card = Card { n: i + 1, statement, y, h };
                y += h + 10.0;
                card
            })
            .collect()
    }

    fn code_lines(card: &Card) -> impl Iterator<Item = (f64, &'static str)> {
        let top = card.y + 39.0 + 10.0 + CODE_LINE / 2.0;
        card.statement.sql.lines().enumerate().map(move |(i, line)| (top + i as f64 * CODE_LINE, line))
    }

    fn counts(&self) -> Vec<(Kind, usize)> {
        [Kind::Update, Kind::Delete, Kind::Insert]
            .into_iter()
            .map(|k| (k, self.statements.iter().filter(|s| s.kind == k).count()))
            .filter(|(_, n)| *n > 0)
            .collect()
    }

    fn badge_w(kind: Kind) -> f64 {
        fonts::width(fonts::MONO, 700, 9.5, 0.57, kind.word()) + 14.0
    }

    fn mono_w(size: f64, weight: u16, text: &str) -> f64 {
        fonts::width(fonts::MONO, weight, size, 0.0, text)
    }

    fn footer_y(&self) -> f64 {
        self.y() + HEIGHT - FOOTER_H
    }

    fn button_w(label: &str) -> f64 {
        fonts::ui(500, 12.5, label) + 24.0
    }

    fn apply_w(&self) -> f64 {
        12.0 + 14.0 + 6.0 + fonts::ui(600, 12.5, "Apply") + 8.0 + super::KbdChip::width("⌘", 10.0) * 2.0 + 3.0 + 8.0
    }
}
