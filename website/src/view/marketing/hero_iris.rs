use damask::Component;

use super::Iris;

/// The hero's set piece: a six-bladed iris drawn large, with the data-type
/// spectrum glowing through the opening. The blades take theme tokens, so
/// the iris is graphite on dark and pewter on light. The caller positions it
/// (`absolute …` or `relative`) — its layers are placed against it.
#[derive(Component)]
pub struct HeroIris {
    pub class: Option<String>,
}

impl HeroIris {
    fn iris() -> Iris {
        Iris { center: 100.0, housing: 97.0, opening: 31.0, twist: 14.0 }
    }

    fn blades(&self) -> Vec<(String, &'static str)> {
        Self::iris().blades().map(|(i, d)| (d, if i % 2 == 0 { "fill-raised" } else { "fill-raised-2" })).collect()
    }
}
