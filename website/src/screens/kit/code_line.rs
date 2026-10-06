use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;
use crate::sql::{self, Kind};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Grammar {
    Sql,
    Json,
}

/// One line of highlighted code, coloured with the app's `sql*` tokens —
/// the editor, the clause bar and JSON cells all paint through this.
#[derive(Component)]
pub struct CodeLine<'a> {
    pub p: &'a Palette,
    pub x: f64,
    pub y: f64,
    pub size: f64,
    pub code: String,
    pub grammar: Option<Grammar>,
}

impl CodeLine<'_> {
    fn spans(&self) -> Vec<(Kind, &str)> {
        match self.grammar.unwrap_or(Grammar::Sql) {
            Grammar::Sql => sql::tokens(&self.code),
            Grammar::Json => sql::json_tokens(&self.code),
        }
    }

    pub fn color(p: &Palette, kind: Kind) -> String {
        p.c(match kind {
            Kind::Keyword => "sqlKeyword",
            Kind::String => "sqlString",
            Kind::Number => "sqlNumber",
            Kind::Comment => "sqlComment",
            Kind::Function => "sqlFunction",
            Kind::Operator => "sqlOperator",
            Kind::Ident | Kind::Space => "sqlIdentifier",
        })
    }

    fn weight(kind: Kind) -> Option<u16> {
        (kind == Kind::Keyword).then_some(500)
    }

    fn style(kind: Kind) -> Option<&'static str> {
        (kind == Kind::Comment).then_some("italic")
    }

    fn family(&self) -> &'static str {
        fonts::MONO
    }

    fn baseline(&self) -> f64 {
        self.y + self.size * 0.36
    }
}
