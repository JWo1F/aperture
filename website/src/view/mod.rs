//! The site's components, one per file, grouped by what they are:
//!
//! - `primitives` — one element each (button, badge, key cap, label, icon)
//! - `layouts` — the document and page structure
//! - `navigation` — header, footer, theme toggle
//! - `surfaces` — things that hold other things (panel, code, screenshot)
//! - `content` — prose-level blocks of a section
//! - `marketing` — the brand mark and the landing page's set pieces
//! - `pages` — one component per output file
//!
//! Colours come from the theme tokens in `ui/app.css`; a raw hex in a
//! template is a palette change that would have to be made twice.
pub mod content;
pub mod layouts;
pub mod marketing;
pub mod navigation;
pub mod pages;
pub mod primitives;
pub mod surfaces;
