use damask::Component;

/// Flips `data-theme` between dark and light and remembers the choice. The
/// two glyphs are both in the markup; CSS shows the one for the theme the
/// page is *not* in, which is what a click will switch to.
#[derive(Component)]
pub struct ThemeToggle;
