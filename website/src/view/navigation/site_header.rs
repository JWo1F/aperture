use damask::Component;

use crate::site::{RELEASES_URL, REPO_URL, Site};

/// The sticky top bar, built like the app's own toolbar: segments split by
/// 1px rails, frosted over whatever scrolls beneath.
#[derive(Component)]
pub struct SiteHeader<'a> {
    pub site: &'a Site,
}

impl SiteHeader<'_> {
    const LINKS: [(&'static str, &'static str); 6] = [
        ("Grid", "/#grid"),
        ("Editor", "/#editor"),
        ("Plans", "/#plans"),
        ("Safety", "/#safety"),
        ("Keys", "/#keys"),
        ("Install", "/#install"),
    ];

    fn repo(&self) -> &'static str {
        REPO_URL
    }

    fn releases(&self) -> &'static str {
        RELEASES_URL
    }
}
