// Ported from NihAV (https://nihav.org, git.nihav.org nihav.git, commit 7552f86), © Kostya Shishkov, AGPL-3.0-or-later.
//! LSB-first bit reader with the semantics of NihAV's `BitReader` in `BitReaderMode::LE`.

use crate::Error;

pub struct BitReader<'a> {
    src: &'a [u8],
    pos: usize, // in bits
}

impl<'a> BitReader<'a> {
    pub fn new(src: &'a [u8]) -> Self {
        BitReader { src, pos: 0 }
    }

    pub fn tell(&self) -> usize {
        self.pos
    }

    /// Bits left until the end of the data.
    pub fn left(&self) -> isize {
        (self.src.len() * 8) as isize - self.pos as isize
    }

    #[inline(always)]
    fn window(&self) -> u64 {
        let byte = self.pos >> 3;
        let mut buf = [0u8; 8];
        let n = self.src.len().saturating_sub(byte).min(8);
        buf[..n].copy_from_slice(&self.src[byte.min(self.src.len())..][..n]);
        u64::from_le_bytes(buf) >> (self.pos & 7)
    }

    #[inline(always)]
    pub fn read(&mut self, nbits: u8) -> Result<u32, Error> {
        if nbits == 0 {
            return Ok(0);
        }
        if nbits > 32 {
            return Err(Error::new("too many bits requested"));
        }
        if self.left() < isize::from(nbits) {
            return Err(Error::new("bitstream end"));
        }
        let v = (self.window() & ((1u64 << nbits) - 1)) as u32;
        self.pos += usize::from(nbits);
        Ok(v)
    }

    #[inline(always)]
    pub fn read_bool(&mut self) -> Result<bool, Error> {
        Ok(self.read(1)? == 1)
    }

    /// Next bits without advancing; zero-padded past the end.
    #[inline(always)]
    pub fn peek(&self, nbits: u8) -> u32 {
        if nbits > 32 {
            return 0;
        }
        (self.window() & ((1u64 << nbits) - 1)) as u32
    }

    pub fn skip(&mut self, nbits: u32) -> Result<(), Error> {
        if self.left() < nbits as isize {
            return Err(Error::new("bitstream end"));
        }
        self.pos += nbits as usize;
        Ok(())
    }

    /// Moves to the next byte boundary.
    pub fn align(&mut self) {
        self.pos = (self.pos + 7) & !7;
    }
}

/// The low `len` bits of `inval` in reverse order.
pub fn reverse_bits(inval: u32, len: u8) -> u32 {
    if len == 0 {
        return 0;
    }
    inval.reverse_bits() >> (32 - len)
}
