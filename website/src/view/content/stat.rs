use damask::Component;

/// A figure and what it measures, in the panel's engraved voice.
#[derive(Component)]
pub struct Stat {
    pub value: String,
    pub label: String,
}
