use damask::Component;

/// A keyboard shortcut as key caps. `keys` is space-separated: `"⌘ ⇧ ↵"`.
#[derive(Component)]
pub struct Kbd {
    pub keys: String,
    /// Smaller caps for use inside running text.
    pub small: Option<bool>,
}

impl Kbd {
    fn caps(&self) -> impl Iterator<Item = &str> {
        self.keys.split_whitespace()
    }

    fn size(&self) -> &'static str {
        if self.small.unwrap_or(false) {
            "h-[1.35rem] min-w-[1.35rem] px-1 text-[0.72rem]"
        } else {
            "h-7 min-w-7 px-1.5 text-[0.8rem]"
        }
    }
}
