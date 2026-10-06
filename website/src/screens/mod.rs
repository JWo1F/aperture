//! The app's screens, redrawn as SVG from demo data and rasterised.
//!
//! Every shot is a Damask component that renders one SVG document from a
//! [`Palette`]; [`render_all`] draws each in both themes at 2x.

pub mod demo;
pub mod fonts;
pub mod icons;
pub mod kit;
pub mod palette;
pub mod scenes;

use std::fs;
use std::path::Path;

use damask::Component;
use resvg::{tiny_skia, usvg};

use palette::{Palette, Theme};

/// The window every shot is drawn in, in logical px.
pub const W: f64 = 1280.0;
pub const H: f64 = 800.0;
/// Pixel density of the rasterised PNGs.
pub const SCALE: f32 = 2.0;

pub struct Shot {
    pub name: &'static str,
    pub alt: &'static str,
    render: fn(&Palette) -> String,
}

pub const SHOTS: &[Shot] = &[
    Shot {
        name: "table",
        alt: "Aperture showing the orders table filtered and sorted, with an edited cell, a deleted row and a queued insert",
        render: |p| scenes::TableShot { p }.render(),
    },
    Shot {
        name: "editor",
        alt: "The SQL editor with a two-statement script, the caret statement highlighted, and its results below",
        render: |p| scenes::EditorShot { p }.render(),
    },
    Shot {
        name: "plan",
        alt: "An EXPLAIN ANALYZE plan as a tree of timed nodes, with advice about a sequential scan",
        render: |p| scenes::PlanShot { p }.render(),
    },
    Shot {
        name: "picker",
        alt: "The timestamptz cell picker open over a cell: segmented date and time, quick actions, and a calendar",
        render: |p| scenes::PickerShot { p }.render(),
    },
    Shot {
        name: "palette",
        alt: "The command palette searching for “ord”, matching tables, an open tab and a command",
        render: |p| scenes::PaletteShot { p }.render(),
    },
    Shot {
        name: "edits",
        alt: "The pending-changes review listing an UPDATE, a DELETE and an INSERT before they run in one transaction",
        render: |p| scenes::EditsShot { p }.render(),
    },
];

impl Shot {
    pub fn svg(&self, theme: Theme) -> String {
        (self.render)(&Palette::load(theme))
    }

    /// Logical size, which the page uses for `width`/`height`.
    pub fn size(&self) -> (u32, u32) {
        (W as u32, H as u32)
    }
}

pub fn find(name: &str) -> &'static Shot {
    SHOTS.iter().find(|s| s.name == name).unwrap_or_else(|| panic!("no shot `{name}`"))
}

/// Writes `<name>-<theme>.png` (and the `.svg` beside it with `keep_svg`).
pub fn render_all(out: &Path, keep_svg: bool) -> Result<(), Box<dyn std::error::Error>> {
    fs::create_dir_all(out)?;
    let mut options = usvg::Options::default();
    *options.fontdb_mut() = fonts::database();
    for shot in SHOTS {
        for theme in Theme::ALL {
            let svg = shot.svg(theme);
            let stem = format!("{}-{}", shot.name, theme.slug());
            if keep_svg {
                fs::write(out.join(format!("{stem}.svg")), &svg)?;
            }
            let tree = usvg::Tree::from_str(&svg, &options).map_err(|e| format!("{stem}: {e}"))?;
            let size = tree.size().to_int_size().scale_by(SCALE).ok_or("empty shot")?;
            let mut pixmap = tiny_skia::Pixmap::new(size.width(), size.height()).ok_or("pixmap")?;
            resvg::render(&tree, tiny_skia::Transform::from_scale(SCALE, SCALE), &mut pixmap.as_mut());
            pixmap.save_png(out.join(format!("{stem}.png")))?;
        }
    }
    Ok(())
}
