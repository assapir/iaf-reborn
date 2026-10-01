//! `*.SSF` — EA installer scripts. We only need the group → folder mapping
//! and the files copied straight from the CD.

#[derive(Debug, Default)]
pub struct InstallScript {
    /// (ESA group, destination dir relative to the install root, `/`-separated)
    pub groups: Vec<(String, String)>,
    /// (source path on the CD, destination dir relative to the install root)
    pub cd_files: Vec<(String, String)>,
}

/// Strip the `[INSTALL_PATH]` / `[EXE_FOLDER]` prefix and normalise separators.
fn rel(path: &str, prefix: &str) -> Option<String> {
    let rest = path.strip_prefix(prefix)?;
    Some(rest.trim_start_matches('\\').replace('\\', "/"))
}

fn quoted(line: &str) -> Vec<&str> {
    line.split('"').skip(1).step_by(2).collect()
}

impl InstallScript {
    pub fn parse(text: &str) -> Self {
        let mut script = Self::default();
        for line in text.lines() {
            let args = quoted(line);
            if line.starts_with("INSTALL_FILES") {
                if let [_, group, dest] = args[..]
                    && let Some(dest) = rel(dest, "[INSTALL_PATH]") {
                        script.groups.push((group.to_string(), dest));
                    }
            } else if line.starts_with("INSTALL_EX_FILES")
                && let [src, dest] = args[..]
                    && let (Some(src), Some(dest)) = (rel(src, "[EXE_FOLDER]"), rel(dest, "[INSTALL_PATH]")) {
                        script.cd_files.push((src, dest));
                    }
        }
        script
    }

    pub fn group_dir(&self, group: &str) -> Option<&str> {
        self.groups.iter().find(|(g, _)| g == group).map(|(_, d)| d.as_str())
    }
}
