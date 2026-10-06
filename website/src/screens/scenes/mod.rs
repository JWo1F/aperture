//! Whole screens: `*Body` is the app in one state, `*Shot` one SVG document.
mod editor_shot;
mod overlay_shots;
mod plan_shot;
pub mod query_body;
mod table_body;
mod table_shot;

pub use editor_shot::EditorShot;
pub use overlay_shots::{EditsShot, PaletteShot, PickerShot};
pub use plan_shot::PlanShot;
pub use query_body::QueryBody;
pub use table_body::{TableBody, tabs};
pub use table_shot::TableShot;
