//! SVG building blocks of the app's chrome, one per surface, sized from the
//! app's own metrics.
pub mod cell_picker;
pub mod clause_bar;
pub mod code_line;
pub mod command_palette;
pub mod grid;
pub mod pagebar;
pub mod pending_edits;
pub mod plan_view;
pub mod query_toolbar;
pub mod section_strip;
pub mod sidebar;
pub mod sql_editor;
pub mod tab_strip;
pub mod toolbar;

mod glyph;
mod kbd_chip;
mod table_glyph;
mod txt;
mod window;

pub use cell_picker::CellPicker;
pub use clause_bar::{Clause, ClauseBar};
pub use code_line::CodeLine;
pub use command_palette::{CommandPalette, Hit};
pub use glyph::Glyph;
pub use grid::Grid;
pub use kbd_chip::KbdChip;
pub use pagebar::{Page, Pagebar};
pub use pending_edits::{PendingEdits, Statement};
pub use plan_view::{Advice, Node, PlanView};
pub use query_toolbar::QueryToolbar;
pub use section_strip::{Section, SectionStrip};
pub use sidebar::Sidebar;
pub use sql_editor::SqlEditor;
pub use tab_strip::{Tab, TabKind, TabStrip};
pub use table_glyph::TableGlyph;
pub use toolbar::Toolbar;
pub use txt::Txt;
pub use window::Window;
