use damask::Component;

/// The opening of a section: an indexed engraved label, the heading as the
/// default slot, and an optional `<p slot="lede">`.
#[derive(Component)]
pub struct SectionHeader {
    pub index: String,
    pub eyebrow: String,
    pub center: Option<bool>,
}

impl SectionHeader {
    fn align(&self) -> &'static str {
        if self.center.unwrap_or(false) { "mx-auto items-center text-center" } else { "items-start" }
    }
}
