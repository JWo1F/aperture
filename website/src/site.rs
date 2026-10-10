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
/// The newest release's DMG itself. Every release attaches it as
/// `Aperture.dmg`, so this one URL always downloads the current version — a
/// link built from pubspec's version would 404 between a version bump and
/// its tag.
pub const DOWNLOAD_URL: &str = "https://github.com/JWo1F/aperture/releases/latest/download/Aperture.dmg";
/// The newest release's Linux tarballs, attached under fixed names for the
/// same reason as the DMG.
pub const LINUX_AMD64_URL: &str =
    "https://github.com/JWo1F/aperture/releases/latest/download/Aperture-linux-amd64.tar.gz";
pub const LINUX_ARM64_URL: &str =
    "https://github.com/JWo1F/aperture/releases/latest/download/Aperture-linux-arm64.tar.gz";
/// The newest release's page: notes, and every older build.
pub const RELEASES_URL: &str = "https://github.com/JWo1F/aperture/releases/latest";

#[derive(Debug, Clone)]
pub struct Site {
    /// `""` or `/segment` — no trailing slash, so joining is `base + path`.
    base: String,
    /// A build for the author's own machine: it carries the design page and
    /// leaves out analytics, so local visits never reach the numbers.
    pub dev: bool,
}

impl Site {
    pub fn new(base: &str, dev: bool) -> Self {
        let trimmed = base.trim().trim_matches('/');
        let base = if trimmed.is_empty() { String::new() } else { format!("/{trimmed}") };
        Self { base, dev }
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
            assert_eq!(Site::new(written, false).url("/"), "/aperture/", "from {written:?}");
        }
        assert_eq!(Site::new("", false).url("/design/"), "/design/");
    }

    #[test]
    fn version_drops_the_build_number() {
        let v = Site::new("", false).version();
        assert!(!v.contains('+') && v.split('.').count() == 3, "{v}");
    }
}
