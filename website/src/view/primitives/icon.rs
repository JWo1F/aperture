use damask::{Attrs, Component};

/// A Hugeicons stroke-rounded glyph — the set the app itself draws with.
#[derive(Component)]
pub struct Icon {
    /// The upstream slug, e.g. `database-01`.
    pub name: String,
    pub class: Option<String>,
    #[prop(rest)]
    pub attrs: Attrs,
}
