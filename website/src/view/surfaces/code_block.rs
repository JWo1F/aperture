use damask::Component;

use crate::sql;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Lang {
    Sql,
    Shell,
}

/// A code listing with build-time highlighting and a copy button.
#[derive(Component)]
pub struct CodeBlock {
    pub code: String,
    pub lang: Lang,
    pub label: Option<String>,
    pub class: Option<String>,
}

impl CodeBlock {
    fn body(&self) -> String {
        match self.lang {
            Lang::Sql => sql::highlight(&self.code),
            Lang::Shell => sql::shell(&self.code),
        }
    }
}
