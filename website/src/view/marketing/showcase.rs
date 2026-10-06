use damask::Component;

use crate::screens;
use crate::site::Site;

pub struct Slide {
    pub shot: &'static str,
    pub label: &'static str,
    pub caption: &'static str,
}

/// Several screens behind one frame, switched by a segmented control — the
/// app's own Info | DDL switch, scaled up.
#[derive(Component)]
pub struct Showcase<'a> {
    pub site: &'a Site,
    pub slides: Vec<Slide>,
}

impl Showcase<'_> {
    fn alt(shot: &str) -> String {
        screens::find(shot).alt.to_string()
    }

    fn size(shot: &str) -> (u32, u32) {
        screens::find(shot).size()
    }
}
