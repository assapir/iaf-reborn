//! Convert original IAF assets into engine-friendly formats.
//!
//! `iaf-convert model <file.x|file.xfr> <out-dir>` — one model → glTF + PNG textures.
//! `iaf-convert planes <install-dir> <out-dir>` — every controllable plane (`*_h.xfr`).

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use iaf_formats::model::Model;
use iaf_tools::gltf::write_model;

fn convert(src: &Path, out_dir: &Path, extra_texture_dirs: &[PathBuf]) -> Result<()> {
    let model = Model::parse(&std::fs::read(src)?).with_context(|| format!("parsing {}", src.display()))?;
    let name = src.file_stem().unwrap().to_string_lossy().to_lowercase();
    let mut dirs = vec![src.parent().unwrap().to_path_buf()];
    dirs.extend_from_slice(extra_texture_dirs);
    let warnings = write_model(&model, &name, &dirs, out_dir)?;
    println!("{} -> {}/{name}.gltf", src.display(), out_dir.display());
    for w in warnings {
        println!("  warning: {w}");
    }
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "model", src, out] => convert(Path::new(src), Path::new(out), &[]),
        [_, "planes", install, out] => {
            let planes = Path::new(install).join("resource/3dobjects/controllableplanes");
            let shared = vec![Path::new(install).join("resource/3dobjects")];
            let mut dirs: Vec<_> = std::fs::read_dir(&planes)?.flatten().map(|e| e.path()).collect();
            dirs.sort();
            for dir in dirs {
                let plane = dir.file_name().unwrap().to_string_lossy().to_string();
                for entry in std::fs::read_dir(&dir)?.flatten() {
                    let p = entry.path();
                    if p.to_string_lossy().ends_with("_h.xfr") {
                        convert(&p, &Path::new(out).join(&plane), &shared)?;
                    }
                }
            }
            Ok(())
        }
        _ => bail!("usage: iaf-convert model <file.x|file.xfr> <out-dir>\n       iaf-convert planes <install-dir> <out-dir>"),
    }
}
