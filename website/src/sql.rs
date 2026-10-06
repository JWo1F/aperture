//! A small SQL lexer for colouring, not for parsing.
//!
//! It knows exactly enough to paint a listing the way the app's editor does —
//! keywords, strings, numbers, comments, function calls, operators — and is
//! shared by the page's code blocks and the rendered screenshots, so the two
//! can never colour the same query differently.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Keyword,
    String,
    Number,
    Comment,
    Function,
    Operator,
    Ident,
    Space,
}

const KEYWORDS: &[&str] = &[
    "select",
    "from",
    "where",
    "and",
    "or",
    "not",
    "in",
    "is",
    "null",
    "as",
    "on",
    "join",
    "left",
    "right",
    "inner",
    "outer",
    "group",
    "by",
    "order",
    "having",
    "limit",
    "offset",
    "insert",
    "into",
    "values",
    "update",
    "set",
    "delete",
    "create",
    "table",
    "index",
    "unique",
    "primary",
    "key",
    "references",
    "default",
    "constraint",
    "check",
    "distinct",
    "case",
    "when",
    "then",
    "else",
    "end",
    "asc",
    "desc",
    "with",
    "returning",
    "explain",
    "analyze",
    "begin",
    "commit",
    "rollback",
    "interval",
    "true",
    "false",
    "like",
    "ilike",
    "between",
    "exists",
    "using",
    "foreign",
    "cascade",
    "now",
    "text",
    "integer",
    "bigint",
    "numeric",
    "boolean",
    "timestamptz",
    "uuid",
    "jsonb",
    "serial",
    "bigserial",
    "varchar",
    "date",
    "if",
    "count",
    "sum",
];

/// Words in `KEYWORDS` that read as functions when called.
const CALLABLE: &[&str] = &["now", "count", "sum", "date"];

pub fn tokens(src: &str) -> Vec<(Kind, &str)> {
    let bytes = src.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let start = i;
        let c = bytes[i];
        let kind = if c.is_ascii_whitespace() {
            while i < bytes.len() && bytes[i].is_ascii_whitespace() {
                i += 1;
            }
            Kind::Space
        } else if src[i..].starts_with("--") {
            i = src[i..].find('\n').map_or(bytes.len(), |n| i + n);
            Kind::Comment
        } else if src[i..].starts_with("/*") {
            i = src[i + 2..].find("*/").map_or(bytes.len(), |n| i + 2 + n + 2);
            Kind::Comment
        } else if c == b'\'' {
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'\'' {
                    if bytes.get(i + 1) == Some(&b'\'') {
                        i += 2;
                        continue;
                    }
                    i += 1;
                    break;
                }
                i += 1;
            }
            Kind::String
        } else if c.is_ascii_digit() {
            while i < bytes.len() && (bytes[i].is_ascii_digit() || bytes[i] == b'.') {
                i += 1;
            }
            Kind::Number
        } else if c.is_ascii_alphabetic() || c == b'_' || c == b'"' {
            if c == b'"' {
                i += 1 + src[i + 1..].find('"').map_or(0, |n| n + 1);
            } else {
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                    i += 1;
                }
            }
            let word = &src[start..i];
            let lower = word.to_ascii_lowercase();
            let called = bytes.get(i) == Some(&b'(');
            if called && (CALLABLE.contains(&lower.as_str()) || !KEYWORDS.contains(&lower.as_str())) {
                Kind::Function
            } else if KEYWORDS.contains(&lower.as_str()) {
                Kind::Keyword
            } else {
                Kind::Ident
            }
        } else {
            // One character at a time, by its UTF-8 width, so multi-byte
            // punctuation (`→`, `·`) stays whole.
            i += src[i..].chars().next().map_or(1, char::len_utf8);
            Kind::Operator
        };
        out.push((kind, &src[start..i]));
    }
    out
}

/// JSON in the same vocabulary, the way the app's grid colours it: keys as
/// identifiers, `true`/`false`/`null` with the numbers, structure as operators.
pub fn json_tokens(src: &str) -> Vec<(Kind, &str)> {
    let bytes = src.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let start = i;
        let kind = match bytes[i] {
            b'"' => {
                i += 1;
                while i < bytes.len() && bytes[i] != b'"' {
                    i += if bytes[i] == b'\\' { 2 } else { 1 };
                }
                i = (i + 1).min(bytes.len());
                let rest = src[i..].trim_start();
                if rest.starts_with(':') { Kind::Ident } else { Kind::String }
            }
            c if c.is_ascii_whitespace() => {
                while i < bytes.len() && bytes[i].is_ascii_whitespace() {
                    i += 1;
                }
                Kind::Space
            }
            c if c.is_ascii_alphanumeric() || c == b'-' || c == b'.' => {
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'-' || bytes[i] == b'.') {
                    i += 1;
                }
                Kind::Number
            }
            _ => {
                i += src[i..].chars().next().map_or(1, char::len_utf8);
                Kind::Operator
            }
        };
        out.push((kind, &src[start..i]));
    }
    out
}

pub fn escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// SQL as HTML spans coloured by the site's `sql-*` tokens.
pub fn highlight(src: &str) -> String {
    tokens(src)
        .into_iter()
        .map(|(kind, text)| {
            let class = match kind {
                Kind::Keyword => "text-sql-keyword font-medium",
                Kind::String => "text-sql-string",
                Kind::Number => "text-sql-number",
                Kind::Comment => "text-sql-comment italic",
                Kind::Function => "text-sql-function",
                Kind::Operator => "text-sql-operator",
                Kind::Ident | Kind::Space => return escape(text),
            };
            format!(r#"<span class="{class}">{}</span>"#, escape(text))
        })
        .collect()
}

/// A shell listing: each command line gets a muted `$` prompt that copying
/// leaves behind, and `#` lines read as comments.
pub fn shell(src: &str) -> String {
    src.lines()
        .map(|line| {
            if line.trim_start().starts_with('#') {
                format!(r#"<span class="text-sql-comment italic">{}</span>"#, escape(line))
            } else {
                format!(r#"<span class="select-none text-ink-faint" aria-hidden="true">$ </span>{}"#, escape(line))
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_cover_the_source_exactly() {
        let src = "select now(), 'it''s' -- done\nfrom t where n >= 1.5 /* c */";
        assert_eq!(tokens(src).iter().map(|(_, t)| *t).collect::<String>(), src);
    }

    #[test]
    fn calls_are_functions_and_bare_words_are_keywords() {
        let kinds: Vec<_> = tokens("count(*) count").into_iter().filter(|(k, _)| *k != Kind::Space).collect();
        assert_eq!(kinds[0], (Kind::Function, "count"));
        assert_eq!(kinds.last(), Some(&(Kind::Keyword, "count")));
    }

    #[test]
    fn json_keys_are_told_from_string_values() {
        let kinds: Vec<_> = json_tokens(r#"{"a": "b", "n": 1.5, "t": true}"#);
        assert!(kinds.contains(&(Kind::Ident, r#""a""#)));
        assert!(kinds.contains(&(Kind::String, r#""b""#)));
        assert!(kinds.contains(&(Kind::Number, "true")));
    }

    #[test]
    fn a_doubled_quote_stays_inside_the_string() {
        assert!(tokens("'it''s'").contains(&(Kind::String, "'it''s'")));
    }
}
