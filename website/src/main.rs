//! Builds the Aperture website into a directory of static files.
//!
//! ```sh
//! cargo run --release -- --out dist --base /aperture
//! ```
//!
//! The stylesheet is compiled by Tailwind before this runs (see
//! `tools/build.sh`); the generator copies `assets/` verbatim, so it refuses
//! to run without `assets/site.css` rather than publish a page with no CSS.

mod screens;
mod site;
mod sql;
mod view;

use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};

use damask::Component;

use site::Site;
use view::pages::{Design, Home};

const ROOT: &str = env!("CARGO_MANIFEST_DIR");

struct Args {
    out: PathBuf,
    base: String,
    keep_svg: bool,
}

impl Args {
    fn parse() -> Result<Self, String> {
        let mut args = Args { out: Path::new(ROOT).join("dist"), base: String::new(), keep_svg: false };
        let mut it = std::env::args().skip(1);
        while let Some(flag) = it.next() {
            match flag.as_str() {
                "--out" => args.out = it.next().ok_or("--out needs a directory")?.into(),
                "--base" => args.base = it.next().ok_or("--base needs a path")?,
                "--svg" => args.keep_svg = true,
                other => return Err(format!("unknown argument `{other}`")),
            }
        }
        Ok(args)
    }
}

fn main() -> Result<(), Box<dyn Error>> {
    let args = Args::parse()?;
    let site = Site::new(&args.base);
    let assets = Path::new(ROOT).join("assets");
    if !assets.join("site.css").exists() {
        return Err("assets/site.css is missing — build through tools/build.sh, which compiles it first".into());
    }

    if args.out.exists() {
        fs::remove_dir_all(&args.out)?;
    }
    fs::create_dir_all(&args.out)?;

    write(&args.out.join("index.html"), &Home { site: &site }.render())?;
    write(&args.out.join("design/index.html"), &Design { site: &site }.render())?;

    copy_dir(&assets, &args.out.join("assets"))?;
    fs::copy(Path::new(ROOT).join("../assets/brand/app_icon.png"), args.out.join("assets/app-icon.png"))?;
    // GitHub Pages runs Jekyll over the upload unless told not to.
    fs::write(args.out.join(".nojekyll"), "")?;

    screens::render_all(&args.out.join("screens"), args.keep_svg)?;
    println!("built {} into {}", site.url("/"), args.out.display());
    Ok(())
}

fn write(path: &Path, html: &str) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(path, html)
}

fn copy_dir(from: &Path, to: &Path) -> std::io::Result<()> {
    fs::create_dir_all(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}
