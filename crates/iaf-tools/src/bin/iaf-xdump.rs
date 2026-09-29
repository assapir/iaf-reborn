//! Print the object tree of a DirectX .X file: `iaf-xdump <file.x|file.xfr>`.

use anyhow::{Context, Result};
use iaf_formats::xfile::{self, XObject};

fn dump(o: &XObject, depth: usize) {
    let preview: Vec<String> = o.values.iter().take(8).map(|v| format!("{v:?}")).collect();
    println!(
        "{:indent$}{} {} [{} values: {}{}]{}",
        "",
        o.template,
        o.name.as_deref().unwrap_or(""),
        o.values.len(),
        preview.join(", "),
        if o.values.len() > 8 { ", …" } else { "" },
        if o.refs.is_empty() { String::new() } else { format!(" refs={:?}", o.refs) },
        indent = depth * 2
    );
    for c in &o.children {
        dump(c, depth + 1);
    }
}

fn main() -> Result<()> {
    let path = std::env::args().nth(1).context("usage: iaf-xdump <file>")?;
    for o in xfile::parse(&std::fs::read(&path)?)? {
        dump(&o, 0);
    }
    Ok(())
}
