use damask::Component;

/// A full-width band of the page, separated from the one above by a hairline.
#[derive(Component)]
pub struct Section {
    pub id: Option<String>,
    pub class: Option<String>,
}
