// Ported from NihAV (https://nihav.org, git.nihav.org nihav.git, commit 7552f86), © Kostya Shishkov, AGPL-3.0-or-later.
use std::mem;
use crate::bits::{BitReader, reverse_bits};
use crate::ivi::*;
use crate::ividsp::*;
use crate::{Error, Frame, Res};

pub fn scale_mv(val: i32, scale: u8) -> i32 {
    (val + (if val > 0 { 1 } else { 0 }) + i32::from(scale) - 1) >> scale
}

#[derive(Clone,Copy)]
pub struct IVICodebook {
    len:    usize,
    bits:   [u8; 16],
    offs:   [u32; 16],
}

impl IVICodebook {
    pub fn init(&self) -> Self {
        let mut cb = *self;
        let mut base: u32 = 0;
        for i in 0..cb.len {
            cb.offs[i] = base;
            base += 1 << cb.bits[i];
        }
        cb
    }
}

pub const IVI_CB_ZERO: IVICodebook = IVICodebook { len: 0, bits: [0; 16], offs: [0; 16] };

pub trait IVICodebookReader {
    fn read_ivi_codebook_desc(&mut self, mb_cb: bool, try_default: bool) -> Res<IVICodebook>;
    fn read_ivi_cb(&mut self, cb: &IVICodebook) -> Res<u32>;
    fn read_ivi_cb_s(&mut self, cb: &IVICodebook) -> Res<i32>;
}

impl<'a> IVICodebookReader for BitReader<'a> {
    fn read_ivi_codebook_desc(&mut self, mb_cb: bool, desc_coded: bool) -> Res<IVICodebook> {
        if !desc_coded {
            if mb_cb {
                Ok(IVI_MB_CB[7].init())
            } else {
                Ok(IVI_BLK_CB[7].init())
            }
        } else {
            let idx = self.read(3)? as usize;
            if idx != 7 {
                if mb_cb {
                    Ok(IVI_MB_CB[idx].init())
                } else {
                    Ok(IVI_BLK_CB[idx].init())
                }
            } else {
                let mut cb = IVI_CB_ZERO;
                cb.len = self.read(4)? as usize;
                if cb.len == 0 { return Err(Error::new("invalid data")); }
                for i in 0..cb.len {
                    cb.bits[i] = self.read(4)? as u8;
                }
                Ok(cb.init())
            }
        }
    }
    #[inline(always)]
    fn read_ivi_cb(&mut self, cb: &IVICodebook) -> Res<u32> {
/*        let pfx = if cb.len == 1 { 0 } else { self.read_code(UintCodeType::LimitedUnary((cb.len - 1) as u32, 0))? as usize };
        let nbits = cb.bits[pfx];
        let mut base: u32 = 0;
        for i in 0..pfx { base += 1 << cb.bits[i]; }
        let rval = self.read(nbits)?;
        let add = reverse_bits(rval, nbits);
        Ok(base + add)*/
        if cb.len > 1 {
            let len = (!self.peek(16)).trailing_zeros() as usize;
            let pfx;
            if len >= cb.len - 1 {
                pfx = cb.len - 1;
                self.skip((cb.len - 1) as u32)?;
            } else {
                pfx = len;
                self.skip((len + 1) as u32)?;
            }
            let nbits = cb.bits[pfx];
            let base = cb.offs[pfx];
            let rval = self.read(nbits)?;
            let add = reverse_bits(rval, nbits);
            Ok(base + add)
        } else {
            let nbits = cb.bits[0];
            Ok(reverse_bits(self.read(nbits)?, nbits))
        }
    }
    #[inline(always)]
    fn read_ivi_cb_s(&mut self, cb: &IVICodebook) -> Res<i32> {
        let v = self.read_ivi_cb(cb)?;
        if v == 0 {
            Ok(0)
        } else {
            let sign = (v & 1) == 1;
            let val = (v >> 1) as i32;
            if sign {
                Ok(val + 1)
            } else {
                Ok(-val)
            }
        }
    }
}

pub const IVI_MB_CB: &[IVICodebook; 8] = &[
    IVICodebook { len:  8, bits: [ 0, 4, 5, 4, 4, 4, 6, 6, 0, 0, 0, 0, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 12, bits: [ 0, 2, 2, 3, 3, 3, 3, 5, 3, 2, 2, 2, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 12, bits: [ 0, 2, 3, 4, 3, 3, 3, 3, 4, 3, 2, 2, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 12, bits: [ 0, 3, 4, 4, 3, 3, 3, 3, 3, 2, 2, 2, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 13, bits: [ 0, 4, 4, 3, 3, 3, 3, 2, 3, 3, 2, 1, 1, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len:  9, bits: [ 0, 4, 4, 4, 4, 3, 3, 3, 2, 0, 0, 0, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 10, bits: [ 0, 4, 4, 4, 4, 3, 3, 2, 2, 2, 0, 0, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 12, bits: [ 0, 4, 4, 4, 3, 3, 2, 3, 2, 2, 2, 2, 0, 0, 0, 0 ], offs: [0; 16] }
];

pub const IVI_BLK_CB: &[IVICodebook; 8] = &[
    IVICodebook { len: 10, bits: [ 1, 2, 3, 4, 4, 7, 5, 5, 4, 1, 0, 0, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 11, bits: [ 2, 3, 4, 4, 4, 7, 5, 4, 3, 3, 2, 0, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 12, bits: [ 2, 4, 5, 5, 5, 5, 6, 4, 4, 3, 1, 1, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 13, bits: [ 3, 3, 4, 4, 5, 6, 6, 4, 4, 3, 2, 1, 1, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 11, bits: [ 3, 4, 4, 5, 5, 5, 6, 5, 4, 2, 2, 0, 0, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 13, bits: [ 3, 4, 5, 5, 5, 5, 6, 4, 3, 3, 2, 1, 1, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len: 13, bits: [ 3, 4, 5, 5, 5, 6, 5, 4, 3, 3, 2, 1, 1, 0, 0, 0 ], offs: [0; 16] },
    IVICodebook { len:  9, bits: [ 3, 4, 4, 5, 5, 5, 6, 5, 5, 0, 0, 0, 0, 0, 0, 0 ], offs: [0; 16] }
];

fn decode_block8x8(br: &mut BitReader, blk_cb: &IVICodebook, rvmap: &RVMap, tables: &TxParams8x8, is_intra: bool, is_2d: bool, prev_dc: &mut i32, quant: u8, coeffs: &mut [i32; 64], transform: TrFunc) -> Res<()> {
    let mut idx: isize = -1;
    let quant_mat = if is_intra { tables.quant_intra } else { tables.quant_inter };
    while idx <= 64 {
        let c = br.read_ivi_cb(blk_cb)?;
        if c == rvmap.eob_sym { break; }
        let run;
        let val: i32;
        if c != rvmap.esc_sym {
            validate!(c < 256);
            run = rvmap.runtab[c as usize] as isize;
            val = rvmap.valtab[c as usize] as i32;
        } else {
            run = (br.read_ivi_cb(blk_cb)? as isize) + 1;
            let lo = br.read_ivi_cb(blk_cb)?;
            let hi = br.read_ivi_cb(blk_cb)?;
            let v = (hi << 6) + lo;
            if v == 0 {
                val = 0; // should not happen but still...
            } else {
                let vv = (v >> 1) as i32;
                if (v & 1) != 0 {
                    val = vv + 1;
                } else {
                    val = -vv;
                }
            }
        }
        idx += run;
        validate!((0..64).contains(&idx));

        let spos = tables.scan[idx as usize];
        let q = (u32::from(quant_mat[spos]) * u32::from(quant)) >> 9;
        if q > 1 {
            let qq = q as i32;
            let bias = (((q ^ 1) - 1) >> 1) as i32;
            coeffs[spos] = val * qq;
            if val > 0 { coeffs[spos] += bias; }
            else       { coeffs[spos] -= bias; }
        } else {
            coeffs[spos] = val;
        }
    }
    if is_intra && is_2d {
        *prev_dc += coeffs[0];
        coeffs[0] = *prev_dc;
    }
    (transform)(coeffs);
    Ok(())
}

fn decode_block4x4(br: &mut BitReader, blk_cb: &IVICodebook, rvmap: &RVMap, tables: &TxParams4x4, is_intra: bool, is_2d: bool, prev_dc: &mut i32, quant: u8, coeffs: &mut [i32; 64], transform: TrFunc) -> Res<()> {
    let mut idx: isize = -1;
    let quant_mat = if is_intra { tables.quant_intra } else { tables.quant_inter };
    while idx <= 64 {
        let c = br.read_ivi_cb(blk_cb)?;
        if c == rvmap.eob_sym { break; }
        let run;
        let val: i32;
        if c != rvmap.esc_sym {
            validate!(c < 256);
            run = rvmap.runtab[c as usize] as isize;
            val = rvmap.valtab[c as usize] as i32;
        } else {
            run = (br.read_ivi_cb(blk_cb)? as isize) + 1;
            let lo = br.read_ivi_cb(blk_cb)?;
            let hi = br.read_ivi_cb(blk_cb)?;
            let v = (hi << 6) + lo;
            if v == 0 {
                val = 0; // should not happen but still...
            } else {
                let vv = (v >> 1) as i32;
                if (v & 1) != 0 {
                    val = vv + 1;
                } else {
                    val = -vv;
                }
            }
        }
        idx += run;
        validate!((0..16).contains(&idx));

        let spos = tables.scan[idx as usize];
        let q = (u32::from(quant_mat[spos]) * u32::from(quant)) >> 9;
        if q > 1 {
            let qq = q as i32;
            let bias = (((q ^ 1) - 1) >> 1) as i32;
            coeffs[spos] = val * qq;
            if val > 0 { coeffs[spos] += bias; }
            else       { coeffs[spos] -= bias; }
        } else {
            coeffs[spos] = val;
        }
    }
    if is_intra && is_2d {
        *prev_dc += coeffs[0];
        coeffs[0] = *prev_dc;
    }
    (transform)(coeffs);
    Ok(())
}

fn put_block(frame: &mut [i16], offs: usize, stride: usize, blk: &[i32], blk_size: usize) {
    for (dline, row) in frame[offs..].chunks_mut(stride).zip(blk.chunks(blk_size)).take(blk_size) {
        for (dst, &src) in dline.iter_mut().zip(row.iter()) {
            *dst = src as i16;
        }
    }
}

fn add_block(frame: &mut [i16], offs: usize, stride: usize, blk: &[i32], blk_size: usize) {
    for (dline, row) in frame[offs..].chunks_mut(stride).zip(blk.chunks(blk_size)).take(blk_size) {
        for (dst, &src) in dline.iter_mut().zip(row.iter()) {
            *dst = dst.wrapping_add(src as i16);
        }
    }
}

#[derive(Default)]
struct FrameData {
    plane_buf:      [Vec<i16>; 3],
    plane_stride:   [usize; 3],
}

fn align(val: usize, bits: u8) -> usize {
    let mask = (1 << bits) - 1;
    (val + mask) & !mask
}

impl FrameData {
    fn realloc(&mut self, pic_hdr: &PictureHeader) {
        let width  = align(pic_hdr.width,  6);
        let height = align(pic_hdr.height, 6);

        let stride = width;
        self.plane_buf[0].resize(stride * height, 0);
        self.plane_stride[0] = stride;
        for plane in 1..3 {
            self.plane_buf[plane].resize((stride >> 1) * (height >> 1), 0);
            self.plane_stride[plane] = stride >> 1;
        }
    }
    fn fill_plane(&self, plane: usize, dst: &mut [u8], w: usize, h: usize) {
        let src      = &self.plane_buf[plane];
        let sstride  = self.plane_stride[plane];
        for (dline, sline) in dst.chunks_mut(w).zip(src.chunks_exact(sstride)).take(h) {
            for (dst, &src) in dline.iter_mut().zip(sline.iter()).take(w) {
                *dst = clip8(src + 128);
            }
        }
    }
}

#[allow(clippy::many_single_char_names)]
fn do_mc(dst: &mut [i16], dstride: usize, src: &[i16], sstride: usize, x: usize, y: usize, l: usize, r: usize, t: usize, b: usize, mv_x: i32, mv_y: i32, is_hpel: bool, blk_size: usize) {
    let (xoff, yoff, mv_mode) = if is_hpel {
            (mv_x >> 1, mv_y >> 1, ((mv_x & 1) + (mv_y & 1) * 2) as u8)
        } else{
            (mv_x, mv_y, 0)
        };
    let xpos = (x as isize) + (xoff as isize);
    let ypos = (y as isize) + (yoff as isize);
    if (xpos < (l as isize)) || ((xpos as usize) + blk_size + ((mv_mode &  1) as usize) > r) ||
       (ypos < (t as isize)) || ((ypos as usize) + blk_size + ((mv_mode >> 1) as usize) > b) {
        return;
    }
    let sidx = (xpos as usize) + (ypos as usize) * sstride;
    if blk_size == 8 {
        ivi_mc_put(dst, dstride, &src[sidx..], sstride, mv_mode, 8, 8);
    } else {
        ivi_mc_put(dst, dstride, &src[sidx..], sstride, mv_mode, 4, 4);
    }
}

pub trait IndeoXParser {
    fn decode_picture_header(&mut self, br: &mut BitReader) -> Res<PictureHeader>;
    fn decode_band_header(&mut self, br: &mut BitReader, pic_hdr: &PictureHeader, plane: usize, band: usize) -> Res<BandHeader>;
    fn decode_mb_info(&mut self, br: &mut BitReader, pic_hdr: &PictureHeader, band_hdr: &BandHeader, tile: &mut IVITile, ref_tile: Option<&IVITile>, mv_scale: u8) -> Res<()>;
    fn recombine_plane(&mut self, src: &[i16], sstride: usize, dst: &mut [u8], dstride: usize, w: usize, h: usize);
}

const MISSING_REF: usize = 42;

pub struct IVIDecoder {
    ftype:      IVIFrameType,
    frames:     [FrameData; 4],
    cur_frame:  usize,
    prev_frame: usize,
    iref_0:     usize,
    iref_1:     usize,
    scal_ref:   usize,

    bands:      Vec<BandHeader>,
    band_tiles: usize,
    tiles:      Vec<IVITile>,
    num_tiles:  [[usize; 4]; 4],
    tile_start: [[usize; 4]; 4],
}

impl IVIDecoder {
    pub fn new() -> Self {
        let mut bands: Vec<BandHeader> = Vec::with_capacity(12);
        bands.resize(12, BandHeader::new_empty(42, 42));
        IVIDecoder {
            ftype:      IVIFrameType::Null,
            frames:     Default::default(),
            cur_frame: 0, prev_frame: MISSING_REF,
            iref_0: MISSING_REF, iref_1: MISSING_REF, scal_ref: MISSING_REF,

            bands,
            band_tiles: 0,
            tiles: Vec::new(), tile_start: [[0; 4]; 4], num_tiles: [[0; 4]; 4],
        }
    }

    fn realloc(&mut self, pic_hdr: &PictureHeader) {
        let planes = 3;

        //self.bands.clear();
        self.tiles.clear();
        self.num_tiles  = [[0; 4]; 4];
        self.tile_start = [[0; 4]; 4];
        let mut tstart: usize = 0;
        for plane in 0..planes {
            let is_luma = (plane != 1) && (plane != 2);
            let bands = if is_luma { pic_hdr.luma_bands } else { pic_hdr.chroma_bands };
            let mut band_w = if is_luma { pic_hdr.width   } else { (pic_hdr.width   + 3) >> 2 };
            let mut band_h = if is_luma { pic_hdr.height  } else { (pic_hdr.height  + 3) >> 2 };
            let mut tile_w = if is_luma { pic_hdr.slice_w } else { (pic_hdr.slice_w + 3) >> 2 };
            let mut tile_h = if is_luma { pic_hdr.slice_h } else { (pic_hdr.slice_h + 3) >> 2 };
            if bands > 1 {
                band_w = (band_w + 1) >> 1;
                band_h = (band_h + 1) >> 1;
                if plane == 0 {
                    tile_w = (tile_w + 1) >> 1;
                    tile_h = (tile_h + 1) >> 1;
                }
            }
            if plane == 0 {
                self.band_tiles = ((band_w + tile_w - 1) / tile_w) * ((band_h + tile_h - 1) / tile_h);
            }
            for band in 0..bands {
                self.tile_start[plane][band] = tstart;
                let band_xoff = if (band & 1) == 1 { band_w } else { 0 };
                let band_yoff = if (band & 2) == 2 { band_h } else { 0 };
                let mut y = 0;
                while y < band_h {
                    let cur_h = if y + tile_h <= band_h { tile_h } else { band_h - y };
                    let mut x = 0;
                    while x < band_w {
                        let cur_w = if x + tile_w <= band_w { tile_w } else { band_w - x };
                        let tile = IVITile::new(band_xoff + x, band_yoff + y, cur_w, cur_h);
                        self.tiles.push(tile);
                        self.num_tiles[plane][band] += 1;
                        tstart += 1;
                        x += tile_w;
                    }
                    y += tile_h;
                }
            }
        }
    }
    fn decode_band(&mut self, pic_hdr: &PictureHeader, dec: &mut dyn IndeoXParser, br: &mut BitReader, plane_no: usize, band_no: usize) -> Res<()> {
        let bidx = match plane_no {
            0 => { band_no },
            _ => { pic_hdr.luma_bands + plane_no - 1 },
        };
        let prev_band = if bidx >= self.bands.len() { BandHeader::new_empty(plane_no, band_no) } else { self.bands[bidx].clone() };
        let mut band = dec.decode_band_header(br, pic_hdr, plane_no, band_no)?;
        if let TxType::None = band.ttype {
            validate!(band.plane_no == prev_band.plane_no);
            validate!(band.band_no  == prev_band.band_no);
            validate!(band.blk_size == prev_band.blk_size);
            band.tr    = prev_band.tr;
            band.ttype = prev_band.ttype;
        };

        let tstart = self.tile_start[band.plane_no][band.band_no];
        let tend   = tstart + self.num_tiles[band.plane_no][band.band_no];
        let mb_size = band.mb_size;
        let (tr, tr_dc) = match band.ttype {
            TxType::Transform4(_) => { ivi_get_transform4x4_funcs(band.tr) },
            TxType::Transform8(_) => { ivi_get_transform8x8_funcs(band.tr) },
            _ => { ivi_get_transform4x4_funcs(band.tr) },
        };
        for tile_no in tstart..tend {
            {
                let tile = &mut self.tiles[tile_no];
                let mb_w = (tile.w + mb_size - 1) / mb_size;
                let mb_h = (tile.h + mb_size - 1) / mb_size;
                tile.mb_w = mb_w;
                tile.mb_h = mb_h;
                tile.mb.clear();
                tile.mb.resize(mb_w * mb_h, MB::new(0, 0));
            }

            let tile_start = br.tell();
            if !br.read_bool()? {
                let res = br.read_bool()?;
                validate!(res);
                let mut len = br.read(8)? as usize;
                if len == 255 {
                    len = br.read(24)? as usize;
                }
                br.align();
                validate!(len > 0);
                let tile_end = (tile_start & !7) + len * 8;
                validate!(tile_end > br.tell());
                validate!(tile_end <= br.tell() + (br.left() as usize));
                {
                    let mut ref_tile: Option<&IVITile> = None;
                    let mv_scale = if (plane_no == 0) && (band_no == 0) { 0 } else {
                            (((self.bands[0].mb_size >> 3) as i8) - ((band.mb_size >> 3) as i8)) as u8
                        };
                    let (ref_tiles, cur_tiles) = self.tiles.split_at_mut(tile_no);
                    let tile = &mut cur_tiles[0];
                    if plane_no != 0 || band_no != 0 {
                        let rtile = &ref_tiles[tile_no % self.band_tiles];
                        if (tile.mb_w == rtile.mb_w) && (tile.mb_h == rtile.mb_h) {
                            ref_tile = Some(rtile);
                        }
                    }
                    dec.decode_mb_info(br, pic_hdr, &band, tile, ref_tile, mv_scale)?;
                }

                self.decode_tile(br, &band, tile_no, tr, tr_dc)?;
                br.align();

                let skip_part = tile_end - br.tell();
                br.skip(skip_part as u32)?;
            } else {
                {
                    let ref_tile: Option<&IVITile>;
                    let mv_scale = if (plane_no == 0) && (band_no == 0) { 0 } else {
                            (((self.bands[0].mb_size >> 3) as i8) - ((band.mb_size >> 3) as i8)) as u8
                        };
                    let (ref_tiles, cur_tiles) = self.tiles.split_at_mut(tile_no);
                    let tile = &mut cur_tiles[0];
                    if plane_no != 0 || band_no != 0 {
                        let rtile = &ref_tiles[0];
                        if (tile.mb_w != rtile.mb_w) || (tile.mb_h != rtile.mb_h) {
                            ref_tile = None;
                        } else {
                            ref_tile = Some(rtile);
                        }
                    } else {
                        ref_tile = None;
                    }
                    let mut mb_idx = 0;
                    for mb_y in 0..tile.mb_h {
                        for mb_x in 0..tile.mb_w {
                            let mut mb = MB::new(tile.pos_x + mb_x * band.mb_size, tile.pos_y + mb_y * band.mb_size);
                            mb.mtype = MBType::Inter;
                            mb.cbp   = 0;
                            if band.inherit_mv {
                                if let Some(tileref) = ref_tile {
                                    let mx = tileref.mb[mb_idx].mv_x;
                                    let my = tileref.mb[mb_idx].mv_y;
                                    mb.mv_x = scale_mv(mx, mv_scale);
                                    mb.mv_y = scale_mv(my, mv_scale);
                                }
                            }
                            tile.mb[mb_idx] = mb;
                            mb_idx += 1;
                        }
                    }
                }
                self.decode_tile(br, &band, tile_no, tr, tr_dc)?;
            }
        }
        self.bands[bidx] = band;
        br.align();
        Ok(())
    }
    fn decode_tile(&mut self, br: &mut BitReader, band: &BandHeader, tile_no: usize, tr: TrFunc, transform_dc: TrFuncDC) -> Res<()> {
        let mut frame = mem::take(&mut self.frames[self.cur_frame]);
        let res = self.decode_tile_into(br, band, tile_no, tr, transform_dc, &mut frame);
        self.frames[self.cur_frame] = frame;
        res
    }
    #[allow(clippy::collapsible_else_if)]
    fn decode_tile_into(&mut self, br: &mut BitReader, band: &BandHeader, tile_no: usize, tr: TrFunc, transform_dc: TrFuncDC, frame: &mut FrameData) -> Res<()> {
        let mut mb_idx = 0;
        let mut prev_dc: i32 = 0;
        let tile = &mut self.tiles[tile_no];

        let stride = frame.plane_stride[band.plane_no];
        let mut dstidx = tile.pos_x + tile.pos_y * stride;
        let dst = &mut frame.plane_buf[band.plane_no];
        let pos_x = tile.pos_x;
        let pos_y = tile.pos_y;
        let tile_w = (tile.w + 15) & !15;
        let tile_h = (tile.h + 15) & !15;
        for mb_y in 0..tile.mb_h {
            for mb_x in 0..tile.mb_w {
                let mb = &mut tile.mb[mb_idx];

                let is_intra = mb.mtype == MBType::Intra;

                if band.mb_size != band.blk_size {
                    let mut cbp = mb.cbp;
                    for blk_no in 0..4 {
                        let mut blk: [i32; 64] = [0; 64];
                        let boff = (blk_no & 1) * band.blk_size + (blk_no >> 1) * band.blk_size * stride + mb_x * band.mb_size;
                        if !is_intra {
                            if let Some(pf) = self.frames.get(self.prev_frame) {
                                do_mc(&mut dst[dstidx + boff..], stride,
                                      &pf.plane_buf[band.plane_no], pf.plane_stride[band.plane_no],
                                      pos_x + mb_x * band.mb_size + (blk_no & 1) * band.blk_size,
                                      pos_y + mb_y * band.mb_size + (blk_no >> 1) * band.blk_size,
                                      pos_x, pos_x + tile_w, pos_y, pos_y + tile_h,
                                      mb.mv_x, mb.mv_y, band.halfpel, band.blk_size);
                            }
                        }
                        if (cbp & 1) != 0 {
                            if let TxType::Transform8(ref params) = band.ttype {
                                decode_block8x8(br, &band.blk_cb, &band.rvmap, params, is_intra, band.tr.is_2d(), &mut prev_dc, mb.q, &mut blk, tr)?;
                                if is_intra {
                                    put_block(dst, dstidx + boff, stride, &blk, 8);
                                } else {
                                    add_block(dst, dstidx + boff, stride, &blk, 8);
                                }
                            }
                            if let TxType::Transform4(ref params) = band.ttype {
                                decode_block4x4(br, &band.blk_cb, &band.rvmap, params, is_intra, band.tr.is_2d(), &mut prev_dc, mb.q, &mut blk, tr)?;
                                if is_intra {
                                    put_block(dst, dstidx + boff, stride, &blk, 4);
                                } else {
                                    add_block(dst, dstidx + boff, stride, &blk, 4);
                                }
                            }
                        } else {
                            if is_intra {
                                (transform_dc)(&mut blk, prev_dc);
                                put_block(dst, dstidx + boff, stride, &blk, band.blk_size);
                            }
                        }
                        cbp >>= 1;
                    }
                } else {
                    let mut blk: [i32; 64] = [0; 64];
                    if !is_intra {
                        if let Some(pf) = self.frames.get(self.prev_frame) {
                            do_mc(&mut dst[dstidx + mb_x * band.blk_size..], stride,
                                  &pf.plane_buf[band.plane_no], pf.plane_stride[band.plane_no],
                                  pos_x + mb_x * band.mb_size,
                                  pos_y + mb_y * band.mb_size,
                                  pos_x, pos_x + tile_w, pos_y, pos_y + tile_h,
                                  mb.mv_x, mb.mv_y, band.halfpel, band.blk_size);
                        }
                    }
                    if mb.cbp != 0 {
                        if let TxType::Transform8(ref params) = band.ttype {
                            decode_block8x8(br, &band.blk_cb, &band.rvmap, params, is_intra, band.tr.is_2d(), &mut prev_dc, mb.q, &mut blk, tr)?;
                        }
                        if let TxType::Transform4(ref params) = band.ttype {
                            decode_block4x4(br, &band.blk_cb, &band.rvmap, params, is_intra, band.tr.is_2d(), &mut prev_dc, mb.q, &mut blk, tr)?;
                        }
                        if is_intra {
                            if band.blk_size == 8 {
                                put_block(dst, dstidx + mb_x * band.blk_size, stride, &blk, 8);
                            } else {
                                put_block(dst, dstidx + mb_x * band.blk_size, stride, &blk, 4);
                            }
                        } else {
                            if band.blk_size == 8 {
                                add_block(dst, dstidx + mb_x * band.blk_size, stride, &blk, 8);
                            } else {
                                add_block(dst, dstidx + mb_x * band.blk_size, stride, &blk, 4);
                            }
                        }
                    } else {
                        if is_intra {
                            (transform_dc)(&mut blk, prev_dc);
                            if band.blk_size == 8 {
                                put_block(dst, dstidx + mb_x * band.blk_size, stride, &blk, 8);
                            } else {
                                put_block(dst, dstidx + mb_x * band.blk_size, stride, &blk, 4);
                            }
                        }
                    }
                }
                mb_idx += 1;
            }
            dstidx += stride * band.mb_size;
        }
        Ok(())
    }

    fn find_unused_frame(&self) -> usize {
        for fno in 0..4 {
            if (fno != self.iref_0) && (fno != self.iref_1) && (fno != self.scal_ref) {
                return fno;
            }
        }
        unreachable!();
    }

    /// Decodes one packet into `out`; returns false for a null frame (`out` untouched).
    pub fn decode_frame(&mut self, dec: &mut dyn IndeoXParser, br: &mut BitReader, out: &mut Frame) -> Res<bool> {
        let pic_hdr = dec.decode_picture_header(br)?;
        self.ftype = pic_hdr.ftype;
        if pic_hdr.ftype.is_null() {
            return Ok(false);
        }

        self.cur_frame = self.find_unused_frame();
        match self.ftype {
            IVIFrameType::Inter => {
                    self.prev_frame = self.iref_0;
                    if self.prev_frame == MISSING_REF {
                        return Err(Error::new("missing reference"));
                    }
                },
            IVIFrameType::InterDroppable | IVIFrameType::InterScal => {
                    self.prev_frame = self.scal_ref;
                    if self.prev_frame == MISSING_REF {
                        return Err(Error::new("missing reference"));
                    }
                },
            _ => {},
        };

        out.resize(pic_hdr.width, pic_hdr.height);
        self.realloc(&pic_hdr);
        self.frames[self.cur_frame].realloc(&pic_hdr);

        for plane in 0..3 {
            let num_bands = if plane == 0 { pic_hdr.luma_bands } else { pic_hdr.chroma_bands };
            for band in 0..num_bands {
                self.decode_band(&pic_hdr, dec, br, plane, band)?;
            }
            let frame = &self.frames[self.cur_frame];
            // Indeo plane order is Y, V, U.
            let (w, h) = out.plane_size(plane);
            let dst = match plane { 0 => &mut out.y, 1 => &mut out.v, _ => &mut out.u };
            if num_bands == 1 {
                frame.fill_plane(plane, dst, w, h);
            } else {
                dec.recombine_plane(&frame.plane_buf[plane], frame.plane_stride[plane], dst, w, w, h);
            }
        }

        match self.ftype {
            IVIFrameType::Intra | IVIFrameType::Inter => {
                    self.iref_1   = self.iref_0;
                    self.iref_0   = self.cur_frame;
                    self.scal_ref = self.cur_frame;
                },
            IVIFrameType::InterScal => {
                    self.scal_ref = self.cur_frame;
                },
            _ => {},
        };

        Ok(true)
    }
}

pub struct RVMap {
    pub eob_sym:    u32,
    pub esc_sym:    u32,
    pub runtab:     [u8; 256],
    pub valtab:     [i8; 256],
}

impl Clone for RVMap {
    fn clone(&self) -> RVMap {
        RVMap { eob_sym: self.eob_sym, esc_sym: self.esc_sym, runtab: self.runtab, valtab: self.valtab }
    }
}

pub const IVI_ZERO_RVMAP: RVMap = RVMap { eob_sym: 0, esc_sym: 0, runtab: [0; 256], valtab: [0; 256] };
