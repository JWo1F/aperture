use damask::{Attrs, Component};

/// The engraved micro-label of an instrument panel: mono, uppercase, wide
/// tracking. `index` prefixes a section number in the accent colour.
#[derive(Component)]
pub struct Label {
    pub index: Option<String>,
    pub class: Option<String>,
    #[prop(rest)]
    pub attrs: Attrs,
}
