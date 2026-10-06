use damask::{Attrs, Component};

#[derive(Clone, Copy, Default, PartialEq, Eq)]
pub enum Variant {
    /// The one accent-filled action a section may have.
    #[default]
    Primary,
    /// Hairline outline on the panel colour.
    Secondary,
    /// Text only, for actions beside a primary one.
    Ghost,
}

/// A call to action. Every action on this site navigates, so it is a link;
/// the label is the default slot so an icon can sit beside it.
#[derive(Component)]
pub struct Button {
    pub href: String,
    pub variant: Option<Variant>,
    /// Leading glyph slug.
    pub icon: Option<String>,
    /// Trailing glyph slug — an arrow for "go somewhere".
    pub trail: Option<String>,
    pub class: Option<String>,
    #[prop(rest)]
    pub attrs: Attrs,
}

impl Button {
    fn skin(&self) -> &'static str {
        match self.variant.unwrap_or_default() {
            Variant::Primary => {
                "bg-accent text-white border-accent hover:bg-accent-hover hover:border-accent-hover shadow-[0_1px_0_0_rgb(255_255_255/0.18)_inset,0_8px_20px_-8px_var(--accent-ring)]"
            }
            Variant::Secondary => "bg-panel text-ink border-line-strong hover:border-ink-faint hover:bg-raised",
            Variant::Ghost => "bg-transparent text-ink-soft border-transparent hover:text-ink hover:bg-raised",
        }
    }
}
