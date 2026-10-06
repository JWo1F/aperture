use damask::Component;

#[derive(Clone, Copy, Default)]
pub enum Tone {
    #[default]
    Neutral,
    Accent,
    Success,
    Warn,
    Danger,
}

/// A small status pill with an optional leading dot.
#[derive(Component)]
pub struct Badge {
    pub tone: Option<Tone>,
    pub dot: Option<bool>,
}

impl Badge {
    fn skin(&self) -> &'static str {
        match self.tone.unwrap_or_default() {
            Tone::Neutral => "text-ink-soft border-line-strong bg-raised",
            Tone::Accent => "text-accent border-accent-ring bg-accent-soft",
            Tone::Success => "text-success border-success/35 bg-success/10",
            Tone::Warn => "text-warn border-warn/35 bg-warn/10",
            Tone::Danger => "text-danger border-danger/35 bg-danger/10",
        }
    }
}
