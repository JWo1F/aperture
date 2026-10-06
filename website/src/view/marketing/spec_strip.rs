use damask::Component;

/// A row of labelled segments split by rails — the app's toolbar rhythm,
/// used to state facts at a glance.
#[derive(Component)]
pub struct SpecStrip {
    pub items: Vec<(&'static str, &'static str)>,
    pub class: Option<String>,
}
