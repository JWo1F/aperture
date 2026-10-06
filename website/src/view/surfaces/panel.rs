use damask::Component;

/// A raised panel with an engraved header strip — the app's synth-panel
/// segment, as a container.
#[derive(Component)]
pub struct Panel {
    pub label: Option<String>,
    /// Right-aligned annotation in the header strip.
    pub meta: Option<String>,
    pub class: Option<String>,
}
