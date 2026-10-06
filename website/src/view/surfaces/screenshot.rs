use damask::Component;

use crate::site::Site;

/// A rendered screen of the app, in both themes. Both images are in the
/// markup and CSS shows the one matching the page, so a theme switch swaps
/// the screenshot without a request round-trip from script.
#[derive(Component)]
pub struct Screenshot<'a> {
    pub site: &'a Site,
    /// The screen's basename under `/screens/`, without the theme suffix.
    pub name: String,
    pub alt: String,
    pub width: u32,
    pub height: u32,
    /// Above the fold: load eagerly and at high priority.
    pub eager: Option<bool>,
    pub class: Option<String>,
}

impl Screenshot<'_> {
    fn src(&self, theme: &str) -> String {
        self.site.url(&format!("/screens/{}-{theme}.png", self.name))
    }

    fn loading(&self) -> &'static str {
        if self.eager.unwrap_or(false) { "eager" } else { "lazy" }
    }
}
