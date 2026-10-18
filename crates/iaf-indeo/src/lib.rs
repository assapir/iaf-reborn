//! Indeo 5 (IV50) video decoder, a port of NihAV's Indeo 5 decoder
//! (https://nihav.org, git.nihav.org nihav.git, commit 7552f86, © Kostya Shishkov, AGPL-3.0-or-later).

// The ported decoder keeps NihAV's arithmetic layout (e.g. `blk[i + 0*8]`) and argument lists.
#![allow(
    clippy::identity_op,
    clippy::erasing_op,
    clippy::too_many_arguments,
    clippy::manual_div_ceil,
    clippy::collapsible_else_if,
    clippy::collapsible_if,
    clippy::needless_late_init,
    clippy::needless_range_loop
)]

macro_rules! validate {
    ($cond:expr) => {
        if !$cond {
            return Err($crate::Error::new(concat!("invalid data: ", stringify!($cond))));
        }
    };
}

mod bits;
mod indeo5;
mod indeo5_tables;
mod ivi;
mod ivibr;
mod ividsp;
mod rvmaps;
mod zigzag;

use bits::BitReader;
use indeo5::Indeo5Parser;
use ivibr::IVIDecoder;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error(pub String);

impl Error {
    pub(crate) fn new(msg: &str) -> Self {
        Error(msg.to_string())
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "indeo: {}", self.0)
    }
}

impl std::error::Error for Error {}

pub(crate) type Res<T> = Result<T, Error>;

/// A planar YUV 4:1:0 picture: chroma planes are (w+3)/4 x (h+3)/4, all planes tightly packed.
#[derive(Debug, Clone, Default)]
pub struct Frame {
    pub width: usize,
    pub height: usize,
    pub y: Vec<u8>,
    pub u: Vec<u8>,
    pub v: Vec<u8>,
}

impl Frame {
    pub(crate) fn resize(&mut self, width: usize, height: usize) {
        self.width = width;
        self.height = height;
        let (cw, ch) = ((width + 3) / 4, (height + 3) / 4);
        self.y.clear();
        self.y.resize(width * height, 0);
        self.u.clear();
        self.u.resize(cw * ch, 0);
        self.v.clear();
        self.v.resize(cw * ch, 0);
    }

    /// Size of the plane with Indeo's index (0 = Y, 1 = V, 2 = U).
    pub(crate) fn plane_size(&self, plane: usize) -> (usize, usize) {
        if plane == 0 {
            (self.width, self.height)
        } else {
            ((self.width + 3) / 4, (self.height + 3) / 4)
        }
    }

    /// RGB8 (`width * height * 3` bytes), BT.601 limited range, chroma nearest-neighbour.
    pub fn to_rgb(&self, out: &mut Vec<u8>) {
        out.clear();
        out.reserve(self.width * self.height * 3);
        let cw = (self.width + 3) / 4;
        for yy in 0..self.height {
            let yrow = &self.y[yy * self.width..][..self.width];
            let crow = (yy / 4) * cw;
            for (x, &luma) in yrow.iter().enumerate() {
                let u = i32::from(self.u[crow + x / 4]) - 128;
                let v = i32::from(self.v[crow + x / 4]) - 128;
                let c = 76309 * (i32::from(luma) - 16) + 32768;
                let r = (c + 104597 * v) >> 16;
                let g = (c - 25675 * u - 53279 * v) >> 16;
                let b = (c + 132201 * u) >> 16;
                out.extend_from_slice(&[r.clamp(0, 255) as u8, g.clamp(0, 255) as u8, b.clamp(0, 255) as u8]);
            }
        }
    }
}

/// Decodes the packets of one Indeo 5 stream in order.
pub struct Decoder {
    ivi: IVIDecoder,
    parser: Indeo5Parser,
    frame: Frame,
}

impl Default for Decoder {
    fn default() -> Self {
        Self::new()
    }
}

impl Decoder {
    pub fn new() -> Self {
        Decoder { ivi: IVIDecoder::new(), parser: Indeo5Parser::new(), frame: Frame::default() }
    }

    /// Decodes one packet. An empty or null-frame packet returns the previous picture unchanged.
    pub fn decode(&mut self, packet: &[u8]) -> Result<&Frame, Error> {
        if !packet.is_empty() {
            let mut br = BitReader::new(packet);
            self.ivi.decode_frame(&mut self.parser, &mut br, &mut self.frame)?;
        }
        Ok(&self.frame)
    }
}
