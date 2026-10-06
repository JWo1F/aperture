use damask::Component;

/// The page measure: 1200px with a 16px gutter on a phone, 32px from `md`.
#[derive(Component)]
pub struct Container {
    pub class: Option<String>,
}
