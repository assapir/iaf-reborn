//! DirectX `.X` files, binary flavour (`xof 0302bin 0032` / `xof 0303bin 0032`).
//!
//! IAF stores all 3D objects this way: `*_h/_m/_l.x` (mesh LODs) and `*.xfr`
//! (frame hierarchy + materials + mesh), exported from 3D Studio via "x3ds".
//!
//! This module turns the token stream into a generic tree of [`XObject`]s whose
//! data members are flattened into a list of [`Value`]s; typed accessors for
//! the templates we use (Mesh, Material, Frame…) live in [`crate::model`].

use crate::Error;
use crate::bytes::{Cursor, latin1};

mod tok {
    pub const NAME: u16 = 1;
    pub const STRING: u16 = 2;
    pub const INTEGER: u16 = 3;
    pub const GUID: u16 = 5;
    pub const INTEGER_LIST: u16 = 6;
    pub const FLOAT_LIST: u16 = 7;
    pub const OBRACE: u16 = 0x0a;
    pub const CBRACE: u16 = 0x0b;
    pub const COMMA: u16 = 0x13;
    pub const SEMICOLON: u16 = 0x14;
    pub const TEMPLATE: u16 = 0x1f;
}

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Int(u32),
    Float(f32),
    Str(String),
}

#[derive(Debug, Clone, Default)]
pub struct XObject {
    /// Template name, e.g. `Mesh`, `Frame`, `Material`.
    pub template: String,
    /// Optional instance name, e.g. `x3ds_mat_p_body`.
    pub name: Option<String>,
    /// Flattened data members in declaration order.
    pub values: Vec<Value>,
    pub children: Vec<XObject>,
    /// `{ name }` references to objects declared elsewhere.
    pub refs: Vec<String>,
}

impl XObject {
    pub fn child(&self, template: &str) -> Option<&XObject> {
        self.children.iter().find(|c| c.template == template)
    }

    pub fn children_of<'a>(&'a self, template: &'a str) -> impl Iterator<Item = &'a XObject> {
        self.children.iter().filter(move |c| c.template == template)
    }
}

/// Reads a flattened value list positionally.
pub struct Values<'a> {
    values: &'a [Value],
    pos: usize,
}

impl<'a> Values<'a> {
    pub fn new(values: &'a [Value]) -> Self {
        Self { values, pos: 0 }
    }

    fn next(&mut self) -> Result<&'a Value, Error> {
        let v = self.values.get(self.pos).ok_or_else(|| Error::Format("X object: not enough data".into()))?;
        self.pos += 1;
        Ok(v)
    }

    pub fn int(&mut self) -> Result<u32, Error> {
        match self.next()? {
            Value::Int(i) => Ok(*i),
            v => Err(Error::Format(format!("X object: expected integer, got {v:?}"))),
        }
    }

    pub fn float(&mut self) -> Result<f32, Error> {
        match self.next()? {
            Value::Float(f) => Ok(*f),
            Value::Int(i) => Ok(*i as f32),
            v => Err(Error::Format(format!("X object: expected float, got {v:?}"))),
        }
    }

    pub fn string(&mut self) -> Result<&'a str, Error> {
        match self.next()? {
            Value::Str(s) => Ok(s),
            v => Err(Error::Format(format!("X object: expected string, got {v:?}"))),
        }
    }

    pub fn floats<const N: usize>(&mut self) -> Result<[f32; N], Error> {
        let mut out = [0.0; N];
        for f in &mut out {
            *f = self.float()?;
        }
        Ok(out)
    }
}

/// Name / string payload: u32 length + Latin-1 bytes.
fn read_name(lx: &mut Cursor) -> Result<String, Error> {
    let len = lx.u32()? as usize;
    Ok(latin1(lx.take(len)?))
}

pub fn parse(data: &[u8]) -> Result<Vec<XObject>, Error> {
    if data.len() < 16 || &data[0..4] != b"xof " {
        return Err(Error::Format("not a DirectX .X file".into()));
    }
    if &data[8..12] != b"bin " {
        return Err(Error::Format(format!("unsupported .X format {:?}", String::from_utf8_lossy(&data[8..12]))));
    }
    if &data[12..16] != b"0032" {
        return Err(Error::Format("only 32-bit float .X files are supported".into()));
    }
    let mut lx = Cursor::new(data, 16);
    let mut objects = Vec::new();
    while !lx.eof() {
        match lx.peek_u16() {
            Some(tok::TEMPLATE) => skip_template(&mut lx)?,
            Some(tok::NAME) => {
                lx.u16()?;
                let template = read_name(&mut lx)?;
                objects.push(parse_object(&mut lx, template)?);
            }
            Some(0) => break, // padding at end of file
            Some(t) => return Err(Error::Format(format!("unexpected token {t:#x} at top level ({})", lx.pos))),
            None => break,
        }
    }
    Ok(objects)
}

fn skip_template(lx: &mut Cursor) -> Result<(), Error> {
    let mut depth = 0;
    loop {
        match lx.u16()? {
            tok::OBRACE => depth += 1,
            tok::CBRACE => {
                depth -= 1;
                if depth == 0 {
                    return Ok(());
                }
            }
            tok::NAME => {
                read_name(lx)?;
            }
            tok::GUID => {
                lx.take(16)?;
            }
            tok::INTEGER => {
                lx.u32()?;
            }
            _ => {}
        }
    }
}

/// Parses an object after its template NAME token has been consumed.
fn parse_object(lx: &mut Cursor, template: String) -> Result<XObject, Error> {
    let mut obj = XObject { template, ..Default::default() };
    if lx.peek_u16() == Some(tok::NAME) {
        lx.u16()?;
        obj.name = Some(read_name(lx)?);
    }
    if lx.u16()? != tok::OBRACE {
        return Err(Error::Format(format!("expected '{{' after {} at {}", obj.template, lx.pos)));
    }
    if lx.peek_u16() == Some(tok::GUID) {
        lx.u16()?;
        lx.take(16)?;
    }
    loop {
        match lx.u16()? {
            tok::CBRACE => return Ok(obj),
            tok::INTEGER_LIST => {
                let n = lx.u32()?;
                for _ in 0..n {
                    obj.values.push(Value::Int(lx.u32()?));
                }
            }
            tok::FLOAT_LIST => {
                let n = lx.u32()?;
                for _ in 0..n {
                    obj.values.push(Value::Float(lx.f32()?));
                }
            }
            tok::INTEGER => {
                let v = lx.u32()?;
                obj.values.push(Value::Int(v));
            }
            tok::STRING => {
                let s = read_name(lx)?;
                obj.values.push(Value::Str(s.trim_end_matches('\0').to_string()));
                // A string is terminated by ';' or ','.
                if matches!(lx.peek_u16(), Some(tok::SEMICOLON | tok::COMMA)) {
                    lx.u16()?;
                }
            }
            tok::SEMICOLON | tok::COMMA => {}
            tok::NAME => {
                let template = read_name(lx)?;
                obj.children.push(parse_object(lx, template)?);
            }
            tok::OBRACE => {
                // Data reference: `{ name }` (optionally with a GUID).
                let mut name = None;
                loop {
                    match lx.u16()? {
                        tok::NAME => name = Some(read_name(lx)?),
                        tok::GUID => {
                            lx.take(16)?;
                        }
                        tok::CBRACE => break,
                        t => return Err(Error::Format(format!("bad token {t:#x} in reference at {}", lx.pos))),
                    }
                }
                obj.refs.extend(name);
            }
            t => return Err(Error::Format(format!("unexpected token {t:#x} in {} at {}", obj.template, lx.pos))),
        }
    }
}
