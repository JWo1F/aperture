use damask::Component;

/// The grid's type colours as a legend: each type in the colour its cells
/// are painted with.
#[derive(Component)]
pub struct Spectrum;

impl Spectrum {
    const TYPES: [(&'static str, &'static str, &'static str); 8] = [
        ("number", "48,213", "text-t-num"),
        ("text", "'shipped'", "text-t-str"),
        ("bool", "true", "text-t-bool"),
        ("uuid", "9f2c…e41a", "text-t-uuid"),
        ("time", "2026-10-04", "text-t-date"),
        ("json", "{\"items\": 3}", "text-t-json"),
        ("foreign key", "↗ customer_id", "text-t-fk"),
        ("null", "NULL", "text-ink-muted italic"),
    ];
}
