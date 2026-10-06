use damask::Component;

use crate::screens::fonts;
use crate::screens::palette::Palette;

/// The 36px window toolbar: traffic lights, history, and — for a table tab —
/// the pending-edits badge and refresh controls before the search field.
#[derive(Component)]
pub struct Toolbar<'a> {
    pub p: &'a Palette,
    pub w: f64,
    /// Staged statements on the active table tab; `None` for other tabs.
    pub pending: Option<u32>,
}

const SEARCH_W: f64 = 220.0;

/// The macOS window controls. Theme-agnostic, like the system draws them.
pub const LIGHTS: [&str; 3] = ["#FF5F57", "#FEBC2E", "#28C840"];

impl Toolbar<'_> {
    fn lights(&self) -> impl Iterator<Item = (f64, &'static str)> {
        LIGHTS.into_iter().enumerate().map(|(i, c)| (20.0 + i as f64 * 20.0, c))
    }

    /// Left cluster: (slug, centre x).
    fn left_icons(&self) -> [(&'static str, f64); 5] {
        [
            ("sidebar-left", 91.0),
            ("arrow-left-01", 126.0),
            ("arrow-right-01", 152.0),
            ("home-01", 195.0),
            ("share-01", 237.0),
        ]
    }

    fn group_rails(&self) -> [f64; 2] {
        [173.5, 216.5]
    }

    fn search_x(&self) -> f64 {
        self.w - 65.0 - SEARCH_W
    }

    fn search_w(&self) -> f64 {
        SEARCH_W
    }

    fn badge_text(&self) -> String {
        self.pending.unwrap_or(0).to_string()
    }

    fn manual_w(&self) -> f64 {
        7.0 + fonts::mono(10.5, "manual") + 4.0 + 11.0 + 7.0
    }

    /// Right-to-left layout of the table-tab actions, ending 6px before the
    /// group rail that precedes the search field.
    fn actions(&self) -> Actions {
        let rail = self.search_x() - 6.5;
        let manual_x = rail - 6.0 - self.manual_w();
        let refresh = manual_x - 11.0;
        let cancel = refresh - 11.0 - 6.0 - 11.0;
        let tick = cancel - 22.0;
        let badge_w = (fonts::mono(11.0, &self.badge_text()) + 16.0).max(26.0);
        let badge_x = tick - 11.0 - 2.0 - badge_w;
        Actions { rail, manual_x, refresh, cancel, tick, badge_x, badge_w }
    }
}

pub struct Actions {
    pub rail: f64,
    pub manual_x: f64,
    pub refresh: f64,
    pub cancel: f64,
    pub tick: f64,
    pub badge_x: f64,
    pub badge_w: f64,
}
