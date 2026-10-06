use damask::Component;

/// A row of the key reference: what it does, and the keys.
#[derive(Component)]
pub struct ShortcutRow {
    pub keys: String,
    pub action: String,
}
