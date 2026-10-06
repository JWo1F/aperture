use damask::Component;

/// An inline link in prose: ink-coloured, with an accent underline that
/// thickens on hover.
#[derive(Component)]
pub struct TextLink {
    pub href: String,
}
