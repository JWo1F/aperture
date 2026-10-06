use damask::Component;

/// One capability: a glyph in a hairline tile, a title, and a sentence or two
/// as the default slot.
#[derive(Component)]
pub struct Feature {
    pub icon: String,
    pub title: String,
}
