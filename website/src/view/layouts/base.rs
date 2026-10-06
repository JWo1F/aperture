use damask::Component;

use crate::site::Site;

/// The document: head, fonts, theme boot, scripts. Everything visible is the
/// default slot.
#[derive(Component)]
pub struct Base<'a> {
    pub site: &'a Site,
    pub title: String,
    pub description: String,
}

impl Base<'_> {
    /// Applies the stored theme before the first paint, and marks the
    /// document as scripted so scroll reveals may start hidden.
    ///
    /// Inline and blocking on purpose: a deferred script runs after the
    /// default theme has painted, which is a white flash on every load for a
    /// reader who chose dark. It is a constant rather than markup because a
    /// `.dmk` reads `{` as a tag wherever it appears, script bodies included.
    const THEME_BOOT: &'static str = r#"<script>
(function () {
  var root = document.documentElement;
  root.classList.add("js");
  var dark;
  try {
    var stored = localStorage.getItem("aperture-theme");
    dark = stored ? stored === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  } catch (e) {
    dark = matchMedia("(prefers-color-scheme: dark)").matches;
  }
  root.dataset.theme = dark ? "dark" : "light";
})();
</script>"#;

    /// Galvani from the CDN, pinned — no bundler between the controllers and
    /// the page.
    const IMPORT_MAP: &'static str = r#"<script type="importmap">
{ "imports": { "galvani": "https://cdn.jsdelivr.net/npm/galvani@0.5.0/src/index.js" } }
</script>"#;

    const FONTS: &'static str = "https://fonts.googleapis.com/css2\
        ?family=Bricolage+Grotesque:opsz,wght@12..96,400;12..96,500;12..96,600;12..96,700\
        &family=Martian+Mono:wght@400;500\
        &family=JetBrains+Mono:wght@400;500\
        &display=swap";

    const ICONS: &'static str = "https://use.hugeicons.com/font/icons.css";

    fn document_title(&self) -> String {
        if self.title.is_empty() {
            "Aperture — a native macOS client for PostgreSQL and SQLite".into()
        } else {
            format!("{} · Aperture", self.title)
        }
    }
}
