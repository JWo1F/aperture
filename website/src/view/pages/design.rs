use damask::Component;

use crate::site::Site;

/// The design system, rendered from the components themselves: every token
/// and every component on one page, in whichever theme the reader picked.
#[derive(Component)]
pub struct Design<'a> {
    pub site: &'a Site,
}

pub struct Swatch {
    pub token: &'static str,
    pub class: &'static str,
    pub note: &'static str,
}

const fn s(token: &'static str, class: &'static str, note: &'static str) -> Swatch {
    Swatch { token, class, note }
}

impl Design<'_> {
    fn palettes(&self) -> Vec<(&'static str, Vec<Swatch>)> {
        vec![
            (
                "Surfaces",
                vec![
                    s("ground", "bg-ground", "page"),
                    s("panel", "bg-panel", "cards, listings"),
                    s("raised", "bg-raised", "header strips, hover"),
                    s("raised-2", "bg-raised-2", "pressed"),
                    s("line-soft", "bg-line-soft", "section rules"),
                    s("line", "bg-line", "borders"),
                    s("line-strong", "bg-line-strong", "key caps, emphasis"),
                ],
            ),
            (
                "Ink",
                vec![
                    s("ink", "bg-ink", "headings, values"),
                    s("ink-soft", "bg-ink-soft", "body"),
                    s("ink-muted", "bg-ink-muted", "secondary, ≥ 4.5:1"),
                    s("ink-faint", "bg-ink-faint", "decoration only"),
                ],
            ),
            (
                "Signal",
                vec![
                    s("accent", "bg-accent", "the one indigo"),
                    s("accent-hover", "bg-accent-hover", "hover"),
                    s("accent-soft", "bg-accent-soft", "selection, tint"),
                    s("success", "bg-success", "applied, live"),
                    s("warn", "bg-warn", "staged, slow"),
                    s("danger", "bg-danger", "delete, refused"),
                ],
            ),
            (
                "Data types",
                vec![
                    s("t-num", "bg-t-num", "numbers"),
                    s("t-str", "bg-t-str", "text"),
                    s("t-bool", "bg-t-bool", "booleans"),
                    s("t-uuid", "bg-t-uuid", "uuids"),
                    s("t-date", "bg-t-date", "dates, times"),
                    s("t-json", "bg-t-json", "json"),
                    s("t-fk", "bg-t-fk", "foreign keys"),
                ],
            ),
            (
                "SQL",
                vec![
                    s("sql-keyword", "bg-sql-keyword", "keywords"),
                    s("sql-string", "bg-sql-string", "strings"),
                    s("sql-number", "bg-sql-number", "numbers"),
                    s("sql-function", "bg-sql-function", "calls"),
                    s("sql-operator", "bg-sql-operator", "punctuation"),
                    s("sql-comment", "bg-sql-comment", "comments"),
                ],
            ),
        ]
    }

    fn type_scale(&self) -> Vec<(&'static str, &'static str, &'static str)> {
        vec![
            ("display", "font-display text-[3.5rem] font-semibold leading-none tracking-[-0.05em]", "A close look."),
            (
                "h2",
                "font-display text-[2.4rem] font-semibold leading-tight tracking-[-0.035em]",
                "Scripts in. Statements out.",
            ),
            ("h3", "font-display text-[1.6rem] font-semibold tracking-[-0.03em]", "A splitter that reads Postgres."),
            ("lede", "text-[1.12rem] leading-relaxed text-ink-soft", "Dense, keyboard-driven, editable to the cell."),
            (
                "body",
                "text-[0.95rem] leading-relaxed text-ink-soft",
                "Rows are addressed by ctid on Postgres and rowid on SQLite.",
            ),
            ("label", "font-label text-[0.66rem] uppercase tracking-[0.16em] text-ink-muted", "Engraved label · 01"),
            ("mono", "font-mono text-[0.88rem]", "select * from orders where total > 25;"),
        ]
    }

    fn icons(&self) -> [&'static str; 16] {
        [
            "database-01",
            "grid-table",
            "filter",
            "sorting-01",
            "pencil-edit-02",
            "shield-01",
            "key-01",
            "link-square-02",
            "code-square",
            "hierarchy-square-01",
            "command",
            "activity-01",
            "file-export",
            "github-01",
            "sun-03",
            "moon-02",
        ]
    }

    fn sample_sql(&self) -> String {
        "select status, count(*) as n\nfrom orders  -- 48k rows\nwhere placed_at > now() - interval '7 days'\ngroup by 1;".into()
    }

    fn sample_shell(&self) -> String {
        "# the whole site, both themes, every screen\n./tools/build.sh".into()
    }

    fn facts(&self) -> Vec<(&'static str, &'static str)> {
        vec![("engines", "PostgreSQL · SQLite"), ("platform", "macOS 12+")]
    }

    fn keys(&self) -> Vec<(&'static str, &'static str)> {
        vec![("⌘ K", "Command palette"), ("⌘ ⇧ ↵", "Run the whole script")]
    }
}
