//! What every page needs to know about the deploy.
//!
//! A GitHub project page lives under `/<repo>/`, a custom domain at the root.
//! That is a deploy-time fact, so every link and asset is built through
//! [`Site::url`] rather than written into a template — a template with a bare
//! `/` in it only works on one of the two.

/// The app's version, read from the pubspec the app itself is built from, so
/// the site cannot advertise a release the app does not have.
const PUBSPEC: &str = include_str!("../../pubspec.yaml");

pub const REPO_URL: &str = "https://github.com/JWo1F/aperture";
/// The newest release's page. Its DMG is named after the version, so the
/// page — not a fixed asset URL — is the link that never goes stale.
pub const RELEASES_URL: &str = "https://github.com/JWo1F/aperture/releases/latest";

#[derive(Debug, Clone)]
pub struct Site {
    /// `""` or `/segment` — no trailing slash, so joining is `base + path`.
    base: String,
}

impl Site {
    pub fn new(base: &str) -> Self {
        let trimmed = base.trim().trim_matches('/');
        let base = if trimmed.is_empty() { String::new() } else { format!("/{trimmed}") };
        Self { base }
    }

    pub fn url(&self, path: &str) -> String {
        debug_assert!(path.starts_with('/'), "site paths are root-relative");
        format!("{}{path}", self.base)
    }

    /// The version name without the build number: `1.38.0+124` → `1.38.0`.
    pub fn version(&self) -> &'static str {
        PUBSPEC
            .lines()
            .find_map(|line| line.strip_prefix("version:"))
            .and_then(|v| v.trim().split('+').next())
            .expect("pubspec.yaml has a version line")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_base_is_normalised_however_it_is_written() {
        for written in ["aperture", "/aperture", "aperture/", "/aperture/"] {
            assert_eq!(Site::new(written).url("/"), "/aperture/", "from {written:?}");
        }
        assert_eq!(Site::new("").url("/design/"), "/design/");
    }

    #[test]
    fn version_drops_the_build_number() {
        let v = Site::new("").version();
        assert!(!v.contains('+') && v.split('.').count() == 3, "{v}");
    }
}
