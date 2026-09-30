//! Little-endian byte reading shared by the parsers.

use crate::Error;

/// Latin-1 decode (every byte is one char), as the 1998 data is 8-bit ANSI text.
pub fn latin1(b: &[u8]) -> String {
    b.iter().map(|&c| c as char).collect()
}

fn truncated(at: usize) -> Error {
    Error::Format(format!("truncated at {at:#x}"))
}

/// `N` bytes at `at`, or a "truncated" error.
pub fn bytes_at<const N: usize>(d: &[u8], at: usize) -> Result<[u8; N], Error> {
    d.get(at..at + N).map(|b| b.try_into().unwrap()).ok_or_else(|| truncated(at))
}

pub fn u16_at(d: &[u8], at: usize) -> Result<u16, Error> {
    bytes_at(d, at).map(u16::from_le_bytes)
}

pub fn i16_at(d: &[u8], at: usize) -> Result<i16, Error> {
    bytes_at(d, at).map(i16::from_le_bytes)
}

pub fn u32_at(d: &[u8], at: usize) -> Result<u32, Error> {
    bytes_at(d, at).map(u32::from_le_bytes)
}

pub fn i32_at(d: &[u8], at: usize) -> Result<i32, Error> {
    bytes_at(d, at).map(i32::from_le_bytes)
}

/// Sequential little-endian reader.
pub struct Cursor<'a> {
    pub data: &'a [u8],
    pub pos: usize,
}

impl<'a> Cursor<'a> {
    pub fn new(data: &'a [u8], pos: usize) -> Self {
        Self { data, pos }
    }

    pub fn eof(&self) -> bool {
        self.pos >= self.data.len()
    }

    pub fn take(&mut self, n: usize) -> Result<&'a [u8], Error> {
        let b = self.data.get(self.pos..self.pos + n).ok_or_else(|| truncated(self.pos))?;
        self.pos += n;
        Ok(b)
    }

    pub fn skip(&mut self, n: usize) -> Result<(), Error> {
        self.take(n).map(|_| ())
    }

    fn array<const N: usize>(&mut self) -> Result<[u8; N], Error> {
        let b = bytes_at(self.data, self.pos)?;
        self.pos += N;
        Ok(b)
    }

    pub fn u8(&mut self) -> Result<u8, Error> {
        self.array::<1>().map(|b| b[0])
    }

    pub fn u16(&mut self) -> Result<u16, Error> {
        self.array().map(u16::from_le_bytes)
    }

    pub fn u32(&mut self) -> Result<u32, Error> {
        self.array().map(u32::from_le_bytes)
    }

    pub fn i32(&mut self) -> Result<i32, Error> {
        self.array().map(i32::from_le_bytes)
    }

    pub fn f32(&mut self) -> Result<f32, Error> {
        self.array().map(f32::from_le_bytes)
    }

    /// The next u16 without consuming it.
    pub fn peek_u16(&self) -> Option<u16> {
        u16_at(self.data, self.pos).ok()
    }

    /// NUL-terminated bytes (the NUL is consumed, not returned).
    pub fn cstr(&mut self) -> Result<&'a [u8], Error> {
        let rest = self.data.get(self.pos..).ok_or_else(|| truncated(self.pos))?;
        let end = rest.iter().position(|&b| b == 0).ok_or_else(|| truncated(self.data.len()))?;
        self.pos += end + 1;
        Ok(&rest[..end])
    }
}
