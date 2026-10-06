use damask::Component;

use crate::site::Site;

/// A page of the site: the document, the header, the footer, and the page's
/// own content as the default slot.
#[derive(Component)]
pub struct Page<'a> {
    pub site: &'a Site,
    pub title: String,
    pub description: String,
}
