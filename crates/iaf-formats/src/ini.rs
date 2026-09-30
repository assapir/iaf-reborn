//! The loose INI dialect used by IAF data files (`*.ibx`, `bd.ibx`, `tgen.ini`):
//! `[SECTION]` headers, `key = value` with tabs/spaces, `;` comments (also
//! trailing), CRLF line endings, Windows-1252 text. Keys keep their case;
//! lookups are case-insensitive like the Win32 profile API the game used.

#[derive(Debug, Clone, Default)]
pub struct Section {
    pub name: String,
    /// In file order; duplicate keys are kept (first one wins on lookup).
    pub entries: Vec<(String, String)>,
}

impl Section {
    pub fn get(&self, key: &str) -> Option<&str> {
        self.entries.iter().find(|(k, _)| k.eq_ignore_ascii_case(key)).map(|(_, v)| v.as_str())
    }

    pub fn f32(&self, key: &str) -> Option<f32> {
        self.get(key)?.trim().parse().ok()
    }

    pub fn i32(&self, key: &str) -> Option<i32> {
        self.get(key)?.trim().parse().ok()
    }
}

#[derive(Debug, Clone, Default)]
pub struct Ini {
    pub sections: Vec<Section>,
}

impl Ini {
    pub fn parse(data: &[u8]) -> Self {
        let text = crate::bytes::latin1(data);
        let mut ini = Ini::default();
        for line in text.lines() {
            let line = line.split(';').next().unwrap_or("").trim();
            if line.is_empty() {
                continue;
            }
            if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
                ini.sections.push(Section { name: name.trim().to_string(), entries: Vec::new() });
            } else if let Some((k, v)) = line.split_once('=') {
                if ini.sections.is_empty() {
                    ini.sections.push(Section::default());
                }
                let section = ini.sections.last_mut().unwrap();
                section.entries.push((k.trim().to_string(), v.trim().to_string()));
            }
        }
        ini
    }

    pub fn section(&self, name: &str) -> Option<&Section> {
        self.sections.iter().find(|s| s.name.eq_ignore_ascii_case(name))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_ibx_style() {
        let ini = Ini::parse(b"; header\r\n[PANEL]\r\n\tFileName\t\t= demopanel.bmp\r\n\tMaskOffsetY1\t= 250\t\t; note\r\n\r\n[Jet-1]\r\nMaxG = 7.5\r\n");
        let panel = ini.section("panel").unwrap();
        assert_eq!(panel.get("filename"), Some("demopanel.bmp"));
        assert_eq!(panel.i32("MaskOffsetY1"), Some(250));
        assert_eq!(ini.section("Jet-1").unwrap().f32("MaxG"), Some(7.5));
    }
}
