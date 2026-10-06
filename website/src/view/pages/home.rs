use damask::Component;

use crate::screens;
use crate::site::{RELEASES_URL, REPO_URL, Site};
use crate::view::marketing::Slide;

/// The landing page.
#[derive(Component)]
pub struct Home<'a> {
    pub site: &'a Site,
}

impl Home<'_> {
    fn repo(&self) -> &'static str {
        REPO_URL
    }

    fn releases(&self) -> &'static str {
        RELEASES_URL
    }

    fn shot(name: &str) -> (String, String, u32, u32) {
        let shot = screens::find(name);
        let (w, h) = shot.size();
        (shot.name.to_string(), shot.alt.to_string(), w, h)
    }

    fn facts(&self) -> Vec<(&'static str, &'static str)> {
        vec![
            ("engines", "PostgreSQL · SQLite"),
            ("platform", "macOS 12+"),
            ("store", "SQLCipher 4"),
            ("built in", "Flutter"),
        ]
    }

    fn grid_slides(&self) -> Vec<Slide> {
        vec![
            Slide {
                shot: "table",
                label: "Grid",
                caption: "Filter, sort, page. Staged changes are painted where they will land.",
            },
            Slide {
                shot: "picker",
                label: "Cell picker",
                caption: "Double-click a cell for an editor that knows its type — here, a timestamptz.",
            },
            Slide {
                shot: "edits",
                label: "Review",
                caption: "Every statement, highlighted, before one transaction sends them all.",
            },
        ]
    }

    const SCRIPT: &'static str = "-- Both survive the splitter: dollar-quoted bodies and E'' strings
create function touch() returns trigger as $$
begin
  new.updated_at := now();  -- not a statement boundary
  return new;
end $$ language plpgsql;

select E'it\\'s fine'; select 1;";

    fn script(&self) -> String {
        Self::SCRIPT.to_string()
    }

    const BUILD: &'static str = "git clone https://github.com/JWo1F/aperture.git
cd aperture
flutter pub get
tool/make_dmg.sh   # → dist/Aperture-<version>.dmg";

    const UNQUARANTINE: &'static str = "xattr -dr com.apple.quarantine /Applications/Aperture.app";

    fn unquarantine(&self) -> String {
        Self::UNQUARANTINE.to_string()
    }

    fn steps(&self) -> [(&'static str, &'static str, &'static str); 3] {
        [
            (
                "01",
                "Download the DMG",
                "From the latest release on GitHub. One universal build for Apple silicon and Intel.",
            ),
            (
                "02",
                "Drag it to Applications",
                "Open the disk image and drop Aperture on the Applications shortcut beside it.",
            ),
            (
                "03",
                "Allow it once",
                "The build is ad-hoc signed, not notarized, so macOS stops the first launch. Click Open Anyway in System Settings → Privacy & Security, or clear the quarantine flag:",
            ),
        ]
    }

    fn build(&self) -> String {
        Self::BUILD.to_string()
    }

    const PASSWORD: &'static str = "op read \"op://Private/atlas-prod/password\"";

    fn password(&self) -> String {
        Self::PASSWORD.to_string()
    }

    fn rules(&self) -> [(&'static str, &'static str); 4] {
        [
            ("Sequential scans", "A full read of a big table behind a selective filter — the index you meant to have."),
            ("Sorts that spill", "work_mem ran out mid-sort and the rest went to disk."),
            ("Estimate mismatches", "The planner expected one row count and got another; stale statistics, usually."),
            ("Batched hashes", "A hash table that didn't fit in memory and was built in passes."),
        ]
    }

    fn keys(&self) -> Vec<(&'static str, &'static str)> {
        vec![
            ("⌘ K", "Jump to any table, tab, query or command"),
            ("⌘ ↵", "Run the statement under the caret"),
            ("⌘ ⇧ ↵", "Run the whole script"),
            ("⌘ [", "Back through tabs, filters and sorts"),
            ("⌘ ]", "Forward again"),
            ("⌘ N", "New query tab"),
            ("⌘ R", "Refresh the table"),
            ("⌘ L", "Activity log — every statement sent"),
            ("⌘ W", "Close the tab"),
        ]
    }
}
