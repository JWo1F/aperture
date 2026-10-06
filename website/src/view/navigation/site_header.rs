use damask::Component;

use crate::site::{REPO_URL, Site};

/// The sticky top bar, built like the app's own toolbar: segments split by
/// 1px rails, frosted over whatever scrolls beneath.
#[derive(Component)]
pub struct SiteHeader<'a> {
    pub site: &'a Site,
}

impl SiteHeader<'_> {
    const LINKS: [(&'static str, &'static str); 5] =
        [("Grid", "/#grid"), ("Editor", "/#editor"), ("Plans", "/#plans"), ("Safety", "/#safety"), ("Keys", "/#keys")];

    fn repo(&self) -> &'static str {
        REPO_URL
    }
}
