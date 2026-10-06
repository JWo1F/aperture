//! The app's two palettes, read from the app's own source.
//!
//! `lib/theme/app_theme.dart` is the single source of truth for every colour
//! the app paints, so the screenshots parse it rather than copy it: a palette
//! change in the app re-colours the site on the next build.

use std::collections::HashMap;

const APP_THEME: &str = include_str!("../../../lib/theme/app_theme.dart");

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Theme {
    Dark,
    Light,
}

impl Theme {
    pub const ALL: [Theme; 2] = [Theme::Dark, Theme::Light];

    pub fn slug(self) -> &'static str {
        match self {
            Theme::Dark => "dark",
            Theme::Light => "light",
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Rgba(pub u8, pub u8, pub u8, pub u8);

pub struct Palette {
    pub theme: Theme,
    colors: HashMap<String, Rgba>,
}

impl Palette {
    pub fn load(theme: Theme) -> Self {
        let marker = match theme {
            Theme::Dark => "const Palette darkPalette = Palette(",
            Theme::Light => "const Palette lightPalette = Palette(",
        };
        let body = APP_THEME.split_once(marker).expect("palette in app_theme.dart").1;
        let body = &body[..body.find(");").expect("palette closes")];
        let colors = body
            .lines()
            .filter_map(|line| {
                let (name, rest) = line.trim().split_once(':')?;
                let hex = rest.trim().strip_prefix("Color(0x")?.get(..8)?;
                Some((name.to_string(), argb(hex)))
            })
            .collect();
        Self { theme, colors }
    }

    pub fn is_dark(&self) -> bool {
        self.theme == Theme::Dark
    }

    fn rgba(&self, name: &str) -> Rgba {
        *self.colors.get(name).unwrap_or_else(|| panic!("no colour `{name}` in the app palette"))
    }

    /// The token as the app paints it, alpha included.
    pub fn c(&self, name: &str) -> String {
        let Rgba(r, g, b, a) = self.rgba(name);
        css(r, g, b, a as f64 / 255.0)
    }

    /// The token's hue at an explicit alpha — `withValues(alpha: a)`.
    pub fn a(&self, name: &str, alpha: f64) -> String {
        let Rgba(r, g, b, _) = self.rgba(name);
        css(r, g, b, alpha)
    }
}

/// A literal colour at an alpha: connection tints and the window controls,
/// which are not palette tokens in the app either.
pub fn hex_alpha(hex: &str, alpha: f64) -> String {
    let n = u32::from_str_radix(hex.trim_start_matches('#'), 16).expect("hex colour");
    css((n >> 16) as u8, (n >> 8) as u8, n as u8, alpha)
}

fn argb(hex: &str) -> Rgba {
    let n = u32::from_str_radix(hex, 16).expect("ARGB hex");
    Rgba((n >> 16) as u8, (n >> 8) as u8, n as u8, (n >> 24) as u8)
}

fn css(r: u8, g: u8, b: u8, a: f64) -> String {
    if a >= 0.999 { format!("#{r:02x}{g:02x}{b:02x}") } else { format!("rgba({r},{g},{b},{a:.3})") }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_palettes_parse_with_the_same_tokens() {
        let dark = Palette::load(Theme::Dark);
        let light = Palette::load(Theme::Light);
        assert!(dark.colors.len() > 40);
        assert_eq!(dark.colors.len(), light.colors.len());
        assert_eq!(dark.c("accent"), "#5b7cfa");
        assert_eq!(dark.c("accentSoft"), "rgba(91,124,250,0.141)");
    }
}
