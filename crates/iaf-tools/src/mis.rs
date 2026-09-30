//! Mission files (`.mis`) and the object database (`.bdb`) — MFC CArchive object graphs from
//! the original mission editor. See docs/formats/mis.md for the
//! meaning of the fields. Produces a generic JSON tree (class name + tagged fields).

use anyhow::{Context, Result, bail};
use serde_json::{Map, Value, json};

const MIS_MAGIC: u32 = 0x68b3f;
const BDB_MAGIC: u32 = 0x4d769;
const JUNK: usize = 0x200;

struct Reader<'a> {
    d: &'a [u8],
    p: usize,
    /// CArchive load map: index 0 = NULL, then classes and objects in load order.
    map: Vec<Option<Value>>,
    classes: Vec<Option<String>>,
    version: i32,
}

impl<'a> Reader<'a> {
    fn new(d: &'a [u8], version: i32) -> Self {
        Self { d, p: 0, map: vec![None], classes: vec![None], version }
    }

    fn raw(&mut self, n: usize) -> Result<&'a [u8]> {
        let v = self.d.get(self.p..self.p + n).with_context(|| format!("truncated at {:#x}", self.p))?;
        self.p += n;
        Ok(v)
    }
    fn u8(&mut self) -> Result<u8> {
        Ok(self.raw(1)?[0])
    }
    fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.raw(2)?.try_into()?))
    }
    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.raw(4)?.try_into()?))
    }
    fn i32(&mut self) -> Result<i32> {
        Ok(i32::from_le_bytes(self.raw(4)?.try_into()?))
    }
    fn f32(&mut self) -> Result<f32> {
        Ok(f32::from_le_bytes(self.raw(4)?.try_into()?))
    }
    fn skip(&mut self, n: usize) -> Result<()> {
        self.raw(n).map(|_| ())
    }

    /// MFC CString: u8 length (0xFF → u16, 0xFFFF → u32), Windows-1252.
    fn cstring(&mut self) -> Result<String> {
        let mut n = self.u8()? as usize;
        if n == 0xff {
            n = self.u16()? as usize;
            if n == 0xffff {
                n = self.u32()? as usize;
            }
        }
        Ok(self.raw(n)?.iter().filter(|&&c| c != 0).map(|&c| c as char).collect())
    }

    /// CArchive::ReadCount.
    fn count(&mut self) -> Result<usize> {
        let n = self.u16()?;
        Ok(if n == 0xffff { self.u32()? as usize } else { n as usize })
    }

    /// Tagged field: u32 id, type char (S/I/B/F), value. Must match `want`.
    fn field(&mut self, o: &mut Map<String, Value>, want: u32) -> Result<()> {
        let id = self.u32()?;
        let t = self.u8()?;
        let v = match t {
            b'S' => json!(self.cstring()?),
            b'I' | b'B' => json!(self.i32()?),
            b'F' => {
                let f = self.f32()?;
                if f.is_finite() { json!(f) } else { Value::Null }
            }
            _ => bail!("bad field type {:?} (id {id:#x}) at {:#x}", t as char, self.p),
        };
        if id != want {
            bail!("expected field {want:#x}, got {id:#x} at {:#x}", self.p);
        }
        o.insert(format!("{id:#x}"), v);
        Ok(())
    }

    fn fields(&mut self, o: &mut Map<String, Value>, ids: &[u32]) -> Result<()> {
        ids.iter().try_for_each(|&id| self.field(o, id))
    }

    /// CDMEDataItem::Read (FUN_00590610): length, 0x14, 0x1e, then 512 junk bytes.
    fn item_base(&mut self, o: &mut Map<String, Value>) -> Result<()> {
        o.insert("_len".into(), json!(self.u32()?));
        self.fields(o, &[0x14, 0x1e])?;
        self.skip(JUNK)
    }

    fn records<const N: usize>(&mut self, fmt: [char; N]) -> Result<Value> {
        let n = self.count()?;
        let mut out = Vec::with_capacity(n);
        for _ in 0..n {
            let mut rec = Vec::with_capacity(N);
            for c in fmt {
                rec.push(if c == 'i' { json!(self.i32()?) } else { json!(self.f32()?) });
            }
            out.push(Value::Array(rec));
        }
        Ok(Value::Array(out))
    }

    /// CArchive::ReadObject.
    fn obj(&mut self) -> Result<Value> {
        let tag = self.u16()?;
        if tag == 0 {
            return Ok(Value::Null);
        }
        let class = if tag == 0xffff {
            self.u16()?; // schema
            let len = self.u16()? as usize;
            let name = String::from_utf8_lossy(self.raw(len)?).to_string();
            self.map.push(None);
            self.classes.push(Some(name.clone()));
            name
        } else if tag & 0x8000 != 0 {
            self.classes
                .get((tag & 0x7fff) as usize)
                .cloned()
                .flatten()
                .with_context(|| format!("bad class back-reference {tag:#x}"))?
        } else {
            return Ok(self.map.get(tag as usize).cloned().flatten().unwrap_or(Value::Null));
        };
        let slot = self.map.len();
        self.map.push(None);
        self.classes.push(None);
        let mut o = Map::new();
        o.insert("_class".into(), json!(class));
        self.read_class(&class, &mut o)?;
        let v = Value::Object(o);
        self.map[slot] = Some(v.clone());
        Ok(v)
    }

    fn read_class(&mut self, class: &str, o: &mut Map<String, Value>) -> Result<()> {
        let v = self.version;
        match class {
            "CObArray" | "CObList" | "CDMEMiscPart" | "CDMETimeVarsPart" | "CDMEPathsPart" | "CDMEEntitiesPart"
            | "CDMEFormationPart" | "CDMEDebriefPart" | "CDMEEventPart" | "CDMEPresentPart" | "CDMEWeaponsPart"
            | "CDMEActionPart" | "CDMEAudioPart" | "CDMEBrainPart" | "CDMEObjectsPart" => {
                let n = self.count()?;
                let items = (0..n).map(|_| self.obj()).collect::<Result<Vec<_>>>()?;
                o.insert("items".into(), Value::Array(items));
            }
            "CDMEMiscItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x44c, 0x456, 0x460, 0x46a, 0x474, 0x47e, 0x488, 0x492, 0x49c, 0x4a6, 0x4b0, 0x4ba, 0x4c4, 0x4ce, 0x4d8, 0x4e2, 0x4ec])?;
                self.skip(JUNK)?;
            }
            "CDMETimeVarsItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x6a4, 0x6ae])?;
                self.skip(JUNK)?;
            }
            "CDMEPathsItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x5dc, 0x5e6])?;
                self.skip(JUNK)?;
                // FUN_00596870: {i32 id, f32 x, f32 y, f32 alt, i32, i32}
                o.insert("points".into(), self.records(['i', 'f', 'f', 'f', 'i', 'i'])?);
            }
            "CDMEEntitiesItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x2bc, 0x2c6, 0x2d0, 0x2da, 0x2e4, 0x2ee, 0x2f8, 0x302, 0x30c, 0x316, 0x320, 0x32a, 0x35c])?;
                let mut slots = Vec::new();
                for _ in 0..7 {
                    let mut s = Map::new();
                    self.fields(&mut s, &[0x334, 0x33e, 0x348, 0x352])?;
                    self.skip(JUNK)?;
                    slots.push(Value::Object(s));
                }
                o.insert("slots".into(), Value::Array(slots));
                let s0 = self.obj()?;
                let s1 = self.obj()?;
                let arm = self.obj()?;
                self.skip(9)?;
                for (key, s) in [("0xec", &s0), ("0xf0", &s1)] {
                    let has_items = s.get("items").and_then(|i| i.as_array()).is_some_and(|i| !i.is_empty());
                    if has_items && v >= 4 {
                        let mut f = Map::new();
                        self.field(&mut f, 0x8b6)?;
                        o.insert(key.into(), f.remove("0x8b6").unwrap_or(Value::Null));
                    } else {
                        self.skip(9)?;
                    }
                }
                o.insert("scripts0".into(), s0);
                o.insert("scripts1".into(), s1);
                o.insert("armament".into(), arm);
                if v >= 8 {
                    o.insert("0xac".into(), json!(self.i32()?));
                    self.skip(0x1e1)?;
                } else {
                    self.skip(0x1e5)?;
                }
            }
            "CDMEScriptObj" => {
                self.item_base(o)?;
                self.fields(o, &[0x834, 0x83e, 0x848, 0x852, 0x85c, 0x866, 0x870, 0x87a, 0x884, 0x88e, 0x898, 0x8a2, 0x8ac])?;
                self.skip(4)?;
                o.insert("raw10".into(), json!(self.i32()?));
                self.skip(0x1f8)?;
            }
            "CArmament" => {
                let hp = (0..24).map(|_| self.u32().map(|x| json!(x))).collect::<Result<Vec<_>>>()?;
                o.insert("hardpoints".into(), Value::Array(hp));
            }
            "CDMEWeaponLoadItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x906, 0x910])?;
                self.u32()?;
                let raw: String = self.raw(0x24)?.iter().map(|b| format!("{b:02x}")).collect();
                o.insert("raw".into(), json!(raw));
                self.skip(JUNK)?;
            }
            "CDMEFormationItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x3e8, 0x3f2, 0x3fc, 0x406])?;
                self.skip(JUNK)?;
                let mut members = Vec::new();
                for _ in 0..2 {
                    let mut s = Map::new();
                    self.fields(&mut s, &[0x410, 0x41a, 0x424])?;
                    self.skip(JUNK)?;
                    members.push(Value::Object(s));
                }
                o.insert("members".into(), Value::Array(members));
                // waypoints {i32 id, f32 x, f32 y, f32 alt, f32 speed, i32 action}
                o.insert("points".into(), self.records(['i', 'f', 'f', 'f', 'f', 'i'])?);
                if v >= 9 {
                    let n = self.count()?;
                    let mut names = Vec::new();
                    for _ in 0..n {
                        let id = self.u32()?;
                        names.push(json!([id, self.cstring()?]));
                    }
                    o.insert("names".into(), Value::Array(names));
                }
            }
            "CDMEDebriefItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x258, 0x262, 0x26c])?;
                self.skip(JUNK)?;
            }
            "CDMEEventItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x384, 0x38e, 0x398, 0x3a2, 0x3ac])?;
                self.skip(JUNK)?;
                let mut conds = Vec::new();
                for _ in 0..3 {
                    let mut s = Map::new();
                    self.fields(&mut s, &[0x3b6, 0x3c0, 0x3ca, 0x3d4])?;
                    if v > 5 {
                        self.fields(&mut s, &[0x3de])?;
                        self.skip(0x1f7)?;
                    } else {
                        self.skip(JUNK)?;
                    }
                    conds.push(Value::Object(s));
                }
                o.insert("conds".into(), Value::Array(conds));
                o.insert("list".into(), self.records(['i', 'i', 'i'])?);
            }
            // ---- .bdb classes
            "CDMEPresentItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x640, 0x64a, 0x654])?;
                if v >= 5 {
                    self.fields(o, &[0x65e])?;
                    self.skip(0x1ee)?;
                } else {
                    self.skip(0x1f7)?;
                }
            }
            "CDMEWeaponsItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x708, 0x712, 0x71c, 0x726, 0x730, 0x73a, 0x744, 0x74e, 0x758, 0x762, 0x76c, 0x776, 0x780, 0x78a])?;
                self.skip(JUNK)?;
            }
            "CDMEActionItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x64, 0x6e, 0x78, 0x82, 0x8c, 0x96, 0xa0, 0xaa, 0xb4, 0xbe, 0xc8])?;
                self.skip(JUNK)?;
            }
            "CDMEAudioItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x12c, 0x136, 0x140])?;
                self.skip(JUNK)?;
            }
            "CDMEBrainRule" => {
                self.item_base(o)?;
                self.fields(o, &[0x190, 0x19a, 0x1a4, 0x1ae])?;
                self.skip(JUNK)?;
                o.insert("list16".into(), self.records(['i', 'i', 'i', 'i'])?);
                o.insert("list20".into(), self.records(['i', 'i', 'i', 'i', 'i'])?);
            }
            "CDMEBrainItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x1f4, 0x1fe, 0x208])?;
                self.u32()?;
                o.insert("rules0".into(), self.obj()?);
                self.u32()?;
                o.insert("rules1".into(), self.obj()?);
                self.skip(JUNK)?;
            }
            "CDMEObjectsItem" => {
                self.item_base(o)?;
                self.fields(o, &[0x514, 0x51e, 0x528, 0x532, 0x53c, 0x546, 0x550, 0x55a, 0x564, 0x56e, 0x578, 0x582, 0x58c, 0x596, 0x5a0, 0x5aa, 0x5b4, 0x5be, 0x5c8, 0x5cd, 0x5d2, 0x5d7])?;
                self.skip(JUNK)?;
                if v < 3 {
                    o.insert("armament".into(), self.obj()?);
                    o.insert("loads".into(), self.obj()?);
                } else {
                    self.u32()?;
                    o.insert("armament".into(), self.obj()?);
                    self.u32()?;
                    o.insert("loads".into(), self.obj()?);
                    self.skip(JUNK)?;
                }
            }
            _ => bail!("unknown class {class}"),
        }
        Ok(())
    }
}

/// Parses a `.mis` file (loader FUN_00589720).
pub fn parse_mission(d: &[u8]) -> Result<Value> {
    let mut r = Reader::new(d, 9);
    let magic = r.u32()?;
    if magic != MIS_MAGIC {
        bail!("not a mission file (magic {magic:#x})");
    }
    r.version = r.u32()? as i32;
    r.skip(0x1fc)?;
    let mut doc = Map::new();
    doc.insert("version".into(), json!(r.version));
    doc.insert("bdb".into(), json!(r.cstring()?));
    for key in ["misc", "timevars", "paths", "entities", "formations", "debrief", "events"] {
        doc.insert(key.into(), r.obj()?);
    }
    Ok(Value::Object(doc))
}

/// Parses the object database (`.bdb`, loader FUN_0058a080). The game reads it with the
/// version of the mission that references it.
pub fn parse_bdb(d: &[u8], version: i32) -> Result<Value> {
    let mut r = Reader::new(d, version);
    let magic = r.u32()?;
    if magic != BDB_MAGIC {
        bail!("not a bdb file (magic {magic:#x})");
    }
    let mut doc = Map::new();
    for key in ["present", "weapons", "actions", "audio", "brains", "objects"] {
        doc.insert(key.into(), r.obj()?);
    }
    Ok(Value::Object(doc))
}
