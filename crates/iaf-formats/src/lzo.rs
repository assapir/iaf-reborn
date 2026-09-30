//! LZO1X decompression (the classic `lzo1x_decompress`), as used by the terrain
//! elevation blocks in `map.ptt` (`FUN_0042c7e0` in iafjets.exe).
//!
//! Bounds-checked: malformed input returns an error instead of panicking.

use crate::Error;

fn corrupt(what: &str) -> Error {
    Error::Format(format!("LZO: {what}"))
}

struct Input<'a> {
    data: &'a [u8],
    pos: usize,
}

impl Input<'_> {
    fn byte(&mut self) -> Result<usize, Error> {
        let b = *self.data.get(self.pos).ok_or_else(|| corrupt("input overrun"))?;
        self.pos += 1;
        Ok(b as usize)
    }

    fn le16(&mut self) -> Result<usize, Error> {
        Ok(self.byte()? | self.byte()? << 8)
    }

    /// Run-length extension: each zero byte adds 255, then the next byte is added to `base`.
    fn extended(&mut self, base: usize) -> Result<usize, Error> {
        let mut n = base;
        loop {
            match self.byte()? {
                0 => n += 255,
                b => return Ok(n + b),
            }
        }
    }

    fn literals(&mut self, out: &mut Vec<u8>, n: usize) -> Result<(), Error> {
        let src = self.data.get(self.pos..self.pos + n).ok_or_else(|| corrupt("literal overrun"))?;
        out.extend_from_slice(src);
        self.pos += n;
        Ok(())
    }
}

fn copy_match(out: &mut Vec<u8>, distance: usize, len: usize) -> Result<(), Error> {
    if distance == 0 || distance > out.len() {
        return Err(corrupt("match distance out of range"));
    }
    let start = out.len() - distance;
    // Byte-by-byte: matches may overlap the bytes they produce.
    for i in 0..len {
        let b = out[start + i];
        out.push(b);
    }
    Ok(())
}

/// Decompresses an LZO1X stream. `expected` is used as a capacity hint and an
/// output-size limit.
pub fn decompress(data: &[u8], expected: usize) -> Result<Vec<u8>, Error> {
    let mut out = Vec::with_capacity(expected);
    let mut ip = Input { data, pos: 0 };
    // `state`: literals copied after the previous instruction (0..3), or 4 after a long literal run.
    let mut state = 0;

    if data.first().is_some_and(|&b| b > 17) {
        let t = ip.byte()? - 17;
        ip.literals(&mut out, t)?;
        state = if t < 4 { t } else { 4 };
    }

    loop {
        if out.len() > expected {
            return Err(corrupt("output larger than expected"));
        }
        let t = ip.byte()?;
        let (distance, len, next);
        if t < 16 {
            match state {
                0 => {
                    // Literal run.
                    let n = if t == 0 { ip.extended(15)? } else { t };
                    ip.literals(&mut out, n + 3)?;
                    state = 4;
                    continue;
                }
                4 => {
                    // 3-byte match right after a long literal run.
                    distance = 1 + 0x800 + (t >> 2) + (ip.byte()? << 2);
                    len = 3;
                }
                _ => {
                    // 2-byte match right after a short literal run.
                    distance = 1 + (t >> 2) + (ip.byte()? << 2);
                    len = 2;
                }
            }
            next = t & 3;
        } else if t >= 64 {
            distance = 1 + ((t >> 2) & 7) + (ip.byte()? << 3);
            len = (t >> 5) + 1;
            next = t & 3;
        } else if t >= 32 {
            let n = if t & 31 == 0 { ip.extended(31)? } else { t & 31 };
            let d = ip.le16()?;
            distance = 1 + (d >> 2);
            len = n + 2;
            next = d & 3;
        } else {
            let n = if t & 7 == 0 { ip.extended(7)? } else { t & 7 };
            let d = ip.le16()?;
            let far = ((t & 8) << 11) + (d >> 2);
            if far == 0 {
                // End-of-stream marker.
                if ip.pos != data.len() {
                    return Err(corrupt("trailing data after end marker"));
                }
                return Ok(out);
            }
            distance = far + 0x4000;
            len = n + 2;
            next = d & 3;
        }
        copy_match(&mut out, distance, len)?;
        ip.literals(&mut out, next)?;
        state = next;
    }
}
