use damask::Component;

use super::iris::Iris;

/// The Aperture mark: a six-bladed iris drawn in one stroke weight, in
/// `currentColor`.
#[derive(Component)]
pub struct ApertureMark {
    pub class: Option<String>,
}

impl ApertureMark {
    fn iris() -> Iris {
        Iris { center: 12.0, housing: 10.25, opening: 4.4, twist: 8.0 }
    }
}
