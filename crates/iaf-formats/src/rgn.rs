//! The CD launcher's `.RGN` files (`poster.rgn`, `buttons.rgn`): named rectangles in the bitmap of the same name.
//! Jauto.exe reads one beside every bitmap it loads (`%s.RGN`, its FUN_00401d84) and looks cells up by name.
//! Format notes: docs/formats/autorun.md.
//!
//! Layout, little-endian: `u32 count`, then per entry a 4-byte name (NUL-padded), `u32 4` (the point count) and four
//! `i32` points (x, y) in the order top-left, top-right, bottom-right, bottom-left. The exe keeps the rectangle
//! (x0, y0)-(x1, y2): left, top, right, bottom, right and bottom exclusive.

use crate::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NamedRect {
    pub name: String,
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

pub fn parse(data: &[u8]) -> Result<Vec<NamedRect>, Error> {
    let i32_at = |o: usize| -> Result<i32, Error> {
        data.get(o..o + 4)
            .map(|b| i32::from_le_bytes(b.try_into().unwrap()))
            .ok_or_else(|| Error::Format("rgn: truncated".into()))
    };
    let count = i32_at(0)?;
    if !(0..=4096).contains(&count) {
        return Err(Error::Format(format!("rgn: bad count {count}")));
    }
    (0..count as usize)
        .map(|i| {
            let o = 4 + i * 40;
            let raw = data.get(o..o + 4).ok_or_else(|| Error::Format("rgn: truncated".into()))?;
            let name = raw.iter().take_while(|&&c| c != 0).map(|&c| c as char).collect();
            if i32_at(o + 4)? != 4 {
                return Err(Error::Format(format!("rgn: entry {i} is not 4 points")));
            }
            let p = |k: usize| i32_at(o + 8 + 4 * k);
            Ok(NamedRect { name, left: p(0)?, top: p(1)?, right: p(2)?, bottom: p(5)? })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_rect() {
        let mut d = 1i32.to_le_bytes().to_vec();
        d.extend(b"B1\0\0");
        for v in [4, 0, 328, 128, 328, 128, 366, 0, 366] {
            d.extend(i32::to_le_bytes(v));
        }
        let r = parse(&d).unwrap();
        assert_eq!(r, vec![NamedRect { name: "B1".into(), left: 0, top: 328, right: 128, bottom: 366 }]);
        assert!(parse(&d[..20]).is_err());
    }
}
