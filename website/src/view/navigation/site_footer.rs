use damask::Component;

use crate::site::{REPO_URL, Site};

#[derive(Component)]
pub struct SiteFooter<'a> {
    pub site: &'a Site,
}

impl SiteFooter<'_> {
    fn repo(&self) -> &'static str {
        REPO_URL
    }
}
