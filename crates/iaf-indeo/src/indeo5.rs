// Ported from NihAV (https://nihav.org, git.nihav.org nihav.git, commit 7552f86), © Kostya Shishkov, AGPL-3.0-or-later.
//! Indeo 5 bitstream headers, macroblock info and the Haar band recombination.

use crate::bits::BitReader;
use crate::indeo5_tables::*;
use crate::ivi::*;
use crate::ivibr::*;
use crate::{Error, Res};

/// The four `hw` x `hh` bands of `src` side by side, each with one replicated column and row added.
fn pad_bands(src: &[i16], sstride: usize, hw: usize, hh: usize) -> (Vec<i16>, usize) {
    let ps = 2 * hw + 2;
    let mut out = vec![0i16; ps * (2 * hh + 2)];
    for band in 0..4 {
        let (sx, sy) = ((band & 1) * hw, (band >> 1) * hh);
        let (dx, dy) = ((band & 1) * (hw + 1), (band >> 1) * (hh + 1));
        for y in 0..=hh {
            let srow = &src[(sy + y.min(hh - 1)) * sstride + sx..][..hw];
            let drow = &mut out[(dy + y) * ps + dx..][..hw + 1];
            drow[..hw].copy_from_slice(srow);
            drow[hw] = srow[hw - 1];
        }
    }
    (out, ps)
}

fn calc_quant(glob_q: u32, qd: i16) -> usize {
    ((glob_q as i16) + qd).clamp(0, 23) as usize
}

pub struct Indeo5Parser {
    mb_cb:          IVICodebook,

    width:          usize,
    height:         usize,
    tile_w:         usize,
    tile_h:         usize,
    luma_bands:     usize,
    chroma_bands:   usize,

    is_hpel:        [bool; 5],
    mb_size:        [usize; 5],
    blk_size:       [usize; 5],
}

impl Indeo5Parser {
    pub fn new() -> Self {
        Indeo5Parser {
            mb_cb:      IVI_CB_ZERO,

            width:          0,
            height:         0,
            tile_w:         0,
            tile_h:         0,
            luma_bands:     0,
            chroma_bands:   0,

            is_hpel:    [false; 5],
            mb_size:    [0; 5],
            blk_size:   [0; 5],
        }
    }
}

fn skip_extension(br: &mut BitReader) -> Res<()> {
    loop {
        let len             = br.read(8)?;
        if len == 0 { break; }
        br.skip(len * 8)?;
    }
    Ok(())
}

impl IndeoXParser for Indeo5Parser {
    fn decode_picture_header(&mut self, br: &mut BitReader) -> Res<PictureHeader> {
        let sync                = br.read(5)?;
        validate!(sync == 0x1F);
        let ftype_idx           = br.read(3)?;
        validate!(ftype_idx < 5);
        let ftype               = INDEO5_FRAME_TYPE[ftype_idx as usize];
        let _fnum               = br.read(8)?;
        if ftype == IVIFrameType::Intra {
            let gop_flags       = br.read(8)?;
            let _hdr_size = if (gop_flags & 0x01) != 0 { br.read(16)? } else { 0 };
            if (gop_flags & 0x20) != 0 {
                br.skip(32)?; // lock word
            }
            self.tile_w = 0;
            self.tile_h = 0;
            if (gop_flags & 0x40) != 0 {
                self.tile_w     = 64 << br.read(2)?;
                self.tile_h = self.tile_w;
            }
            validate!(self.tile_w < 256);
            self.luma_bands     = (br.read(2)? * 3 + 1) as usize;
            self.chroma_bands   = (br.read(1)? * 3 + 1) as usize;
            validate!((self.luma_bands == 4) || (self.luma_bands == 1));
            validate!(self.chroma_bands == 1);
            let pic_size_idx    = br.read(4)? as usize;
            let w;
            let h;
            if pic_size_idx < 15 {
                w = INDEO5_PICTURE_SIZE_TAB[pic_size_idx][0];
                h = INDEO5_PICTURE_SIZE_TAB[pic_size_idx][1];
            } else {
                h               = br.read(13)? as usize;
                w               = br.read(13)? as usize;
            }
            validate!((w != 0) && (h != 0));
            self.width  = w;
            self.height = h;

            validate!((gop_flags & 0x02) == 0);
            if self.tile_w == 0 {
                self.tile_w = w;
                self.tile_h = h;
            }
            for b in 0..self.luma_bands+self.chroma_bands {
                self.is_hpel[b]     = br.read_bool()?;
                let mb_scale        = br.read(1)?;
                self.blk_size[b]    = 8 >> br.read(1)?;
                self.mb_size[b]     = self.blk_size[b] << (1 - mb_scale);
                let ext_tr          = br.read_bool()?;
                validate!(!ext_tr);
                let end_marker      = br.read(2)?;
                validate!(end_marker == 0);
            }
            if (gop_flags & 0x08) != 0 {
                let align       = br.read(3)?;
                validate!(align == 0);
                if br.read_bool()? {
                    br.skip(24)?; // transparency color
                }
            }
            br.align();
            br.skip(23)?;
            if br.read_bool()? { // gop extension
                loop {
                    let v       = br.read(16)?;
                    if (v & 0x8000) == 0 { break; }
                }
            }
            br.align();
        }
        if ftype.is_null() {
            br.align();
            return Ok(PictureHeader::new_null(ftype));
        }
        let flags               = br.read(8)?;
        let _size = if (flags & 0x01) != 0 { br.read(24)? } else { 0 };
        let _checksum = if (flags & 0x10) != 0 { br.read(16)? } else { 0 };
        if (flags & 0x20) != 0 {
            skip_extension(br)?;
        }
        let in_q = (flags & 0x08) != 0;
        self.mb_cb              = br.read_ivi_codebook_desc(true, (flags & 0x40) != 0)?;
        br.skip(3)?;
        br.align();

        Ok(PictureHeader::new(ftype, self.width, self.height, self.tile_w, self.tile_h, self.luma_bands, self.chroma_bands, in_q))
    }

    fn decode_band_header(&mut self, br: &mut BitReader, _pic_hdr: &PictureHeader, plane_no: usize, band_no: usize) -> Res<BandHeader> {
        let band_flags      = br.read(8)?;

        if (band_flags & 0x01) != 0 {
            br.align();
            return Ok(BandHeader::new_empty(plane_no, band_no));
        }
        let inherit_mv = (band_flags & 0x02) != 0;
        let has_qdelta = (band_flags & 0x04) != 0;
        let inherit_qd = ((band_flags & 0x08) != 0) || !has_qdelta;
        let data_size: usize;
        if (band_flags & 0x80) != 0 {
            data_size       = br.read(24)? as usize;
            validate!(data_size >= 4);
        } else {
            data_size = 0;
        }
        validate!(data_size <= ((br.left() / 8) as usize) + 4);

        let num_corr: usize;
        let mut corr_map: [u8; CORR_MAP_SIZE] = [0; CORR_MAP_SIZE];
        if (band_flags & 0x10) != 0 {
            num_corr = br.read(8)? as usize;
            validate!(num_corr*2 <= CORR_MAP_SIZE);
            for el in corr_map[..num_corr*2].iter_mut() {
                *el = br.read(8)? as u8;
            }
        } else {
            num_corr = 0;
        }
        let rvmap_idx = if (band_flags & 0x40) != 0 { br.read(3)? as usize } else { 8 };
        let blk_cb = br.read_ivi_codebook_desc(false, (band_flags & 0x80) != 0)?;
        if br.read_bool()? {
            br.skip(16)?; // checksum
        }
        let band_q          = br.read(5)?;
        if (band_flags & 0x20) != 0 {
            skip_extension(br)?;
        }
        br.align();

        let tr;
        let txtype;
        let band_id = if plane_no == 0 { band_no } else { self.luma_bands };
        match plane_no {
            0 => {
                    let scan = INDEO5_SCAN8X8[band_no];
                    let qintra;
                    let qinter;
                    validate!(self.blk_size[band_id] == 8);
                    match band_no {
                        0 => {
                                tr = IVITransformType::Slant(TSize::T8x8, TDir::TwoD);
                                if self.luma_bands == 1 {
                                    qintra = INDEO5_Q8_INTRA[0];
                                    qinter = INDEO5_Q8_INTER[0];
                                } else {
                                    qintra = INDEO5_Q8_INTRA[1];
                                    qinter = INDEO5_Q8_INTER[1];
                                }
                            },
                        1 => {
                                tr = IVITransformType::Slant(TSize::T8x8, TDir::Row);
                                qintra = INDEO5_Q8_INTRA[2];
                                qinter = INDEO5_Q8_INTER[2];
                            },
                        2 => {
                                tr = IVITransformType::Slant(TSize::T8x8, TDir::Col);
                                qintra = INDEO5_Q8_INTRA[3];
                                qinter = INDEO5_Q8_INTER[3];
                            },
                        3 => {
                                tr = IVITransformType::None(TSize::T8x8);
                                qintra = INDEO5_Q8_INTRA[4];
                                qinter = INDEO5_Q8_INTER[4];
                            },
                        _ => { unreachable!(); }
                    };
                    txtype = TxType::Transform8(TxParams8x8::new(qintra, qinter, scan));
                },
            1 | 2 => {
                    validate!(self.blk_size[band_id] == 4);
                    tr = IVITransformType::Slant(TSize::T4x4, TDir::TwoD);
                    let scan = INDEO5_SCAN4X4;
                    let qintra = INDEO5_Q4_INTRA;
                    let qinter = INDEO5_Q4_INTER;
                    txtype = TxType::Transform4(TxParams4x4::new(qintra, qinter, scan));
                },
            _ => { unreachable!(); }
        };

        Ok(BandHeader::new(plane_no, band_no, self.mb_size[band_id], self.blk_size[band_id], self.is_hpel[band_id], inherit_mv, has_qdelta, inherit_qd, band_q, rvmap_idx, num_corr, corr_map, blk_cb, tr, txtype))
    }

    #[allow(clippy::cognitive_complexity)]
    #[allow(clippy::collapsible_else_if)]
    fn decode_mb_info(&mut self, br: &mut BitReader, pic_hdr: &PictureHeader, band: &BandHeader, tile: &mut IVITile, ref_tile: Option<&IVITile>, mv_scale: u8) -> Res<()> {
        let mut mv_x = 0;
        let mut mv_y = 0;
        let band_id = if pic_hdr.luma_bands == 4 { band.band_no + 1 } else { 0 };
        let mut mb_idx = 0;
        for mb_y in 0..tile.mb_h {
            for mb_x in 0..tile.mb_w {
                let mut mb = MB::new(tile.pos_x + mb_x * band.mb_size, tile.pos_y + mb_y * band.mb_size);
                if !br.read_bool()? {
                    if pic_hdr.ftype.is_intra() {
                        mb.mtype = MBType::Intra;
                    } else if band.inherit_mv {
                        if let Some(tileref) = ref_tile {
                            mb.mtype = tileref.mb[mb_idx].mtype;
                        } else {
                            return Err(Error::new("missing reference"));
                        }
                    } else {
                        mb.mtype = if br.read_bool()? { MBType::Inter } else { MBType::Intra };
                    }
                    if band.mb_size == band.blk_size {
                        mb.cbp = br.read(1)? as u8;
                    } else {
                        mb.cbp = br.read(4)? as u8;
                    }
                    let q;
                    if band.has_qdelta {
                        if band.inherit_qd {
                            if let Some(tileref) = ref_tile {
                                mb.qd = tileref.mb[mb_idx].qd;
                                q = calc_quant(band.quant, mb.qd);
                            } else {
                                return Err(Error::new("missing reference"));
                            }
                        } else if (mb.cbp != 0) || ((band.plane_no == 0) && (band.band_no == 0) && pic_hdr.in_q) {
                            mb.qd = br.read_ivi_cb_s(&self.mb_cb)? as i16;
                            q = calc_quant(band.quant, mb.qd);
                        } else {
                            q = band.quant as usize;
                        }
                    } else {
                        q = band.quant as usize;
                    }

                    if mb.mtype == MBType::Intra {
                        if band.blk_size == 8 {
                            mb.q = INDEO5_QSCALE8_INTRA[band_id][q];
                        } else {
                            mb.q = INDEO5_QSCALE4_INTRA[q];
                        }
                    } else {
                        if band.blk_size == 8 {
                            mb.q = INDEO5_QSCALE8_INTER[band_id][q];
                        } else {
                            mb.q = INDEO5_QSCALE4_INTER[q];
                        }
                    }

                    if mb.mtype != MBType::Intra {
                        if band.inherit_mv {
                            if let Some(tileref) = ref_tile {
                                let mx = tileref.mb[mb_idx].mv_x;
                                let my = tileref.mb[mb_idx].mv_y;
                                if mv_scale == 0 {
                                    mb.mv_x = mx;
                                    mb.mv_y = my;
                                } else {
                                    mb.mv_x = scale_mv(mx, mv_scale);
                                    mb.mv_y = scale_mv(my, mv_scale);
                                }
                            }
                        } else {
                            mv_y += br.read_ivi_cb_s(&self.mb_cb)?;
                            mv_x += br.read_ivi_cb_s(&self.mb_cb)?;
                            mb.mv_x = mv_x;
                            mb.mv_y = mv_y;
                        }
                    }
                } else {
                    validate!(!pic_hdr.ftype.is_intra());
                    mb.mtype = MBType::Inter;
                    mb.cbp   = 0;
                    mb.qd    = 0;
                    if (band.plane_no == 0) && (band.band_no == 0) && pic_hdr.in_q {
                        mb.qd = br.read_ivi_cb_s(&self.mb_cb)? as i16;
                        let q = calc_quant(band.quant, mb.qd);
                        if mb.mtype == MBType::Intra {
                            if band.blk_size == 8 {
                                mb.q = INDEO5_QSCALE8_INTRA[band_id][q];
                            } else {
                                mb.q = INDEO5_QSCALE4_INTRA[q];
                            }
                        } else {
                            if band.blk_size == 8 {
                                mb.q = INDEO5_QSCALE8_INTER[band_id][q];
                            } else {
                                mb.q = INDEO5_QSCALE4_INTER[q];
                            }
                        }
                    }
                    if band.inherit_mv {
                        if let Some(tileref) = ref_tile {
                            let mx = tileref.mb[mb_idx].mv_x;
                            let my = tileref.mb[mb_idx].mv_y;
                            if mv_scale == 0 {
                                mb.mv_x = mx;
                                mb.mv_y = my;
                            } else {
                                mb.mv_x = scale_mv(mx, mv_scale);
                                mb.mv_y = scale_mv(my, mv_scale);
                            }
                        }
                    }
                }
                tile.mb[mb_idx] = mb;
                mb_idx += 1;
            }
        }
        br.align();
        Ok(())
    }

    #[allow(clippy::identity_op)]
    fn recombine_plane(&mut self, src: &[i16], sstride: usize, dst: &mut [u8], dstride: usize, w: usize, h: usize) {
        // Deviation from NihAV, which stops one sample short of the right and bottom edge (leaving the
        // last two columns and rows unwritten): every band gets one replicated column and row, so the
        // same filter also covers the edge.
        let hw = w / 2;
        let hh = h / 2;
        let (padded, sstride) = pad_bands(src, sstride, hw, hh);
        let src = &padded[..];
        let mut idx0 = 0;
        let mut idx1 = hw + 1;
        let mut idx2 = (hh + 1) * sstride;
        let mut idx3 = idx2 + idx1;
        let mut bidx1 = idx1;
        let mut bidx3 = idx3;
        let mut oidx0 = 0;
        let mut oidx1 = dstride;
        let filt_lo = |a: i16, b: i16| a + b;
        let filt_hi = |a: i16, b: i16, c: i16| a - b * 6 + c;

        for _ in 0..hh {
            let mut b0_1 = src[idx0];
            let mut b0_2 = src[idx0 + sstride];
            let mut b1_1 = src[bidx1];
            let mut b1_2 = src[idx1];
            let mut b1_3 = filt_hi(b1_1, b1_2, src[idx1 + sstride]);
            let mut b2_1;
            let mut b2_2 = src[idx2];
            let mut b2_3 = b2_2;
            let mut b2_4;
            let mut b2_5 = src[idx2 + sstride];
            let mut b2_6 = b2_5;
            let mut b3_1;
            let mut b3_2 = src[bidx3];
            let mut b3_3 = b3_2;
            let mut b3_4;
            let mut b3_5 = src[idx3];
            let mut b3_6 = b3_5;
            let mut b3_8 = filt_hi(b3_2, b3_5, src[idx3 + sstride]);
            let mut b3_9 = b3_8;
            let mut b3_7;

            for x in 0..hw {
                b2_1 = b2_2;
                b2_2 = b2_3;
                b2_4 = b2_5;
                b2_5 = b2_6;
                b3_1 = b3_2;
                b3_2 = b3_3;
                b3_4 = b3_5;
                b3_5 = b3_6;
                b3_7 = b3_8;
                b3_8 = b3_9;

                let tmp0 = b0_1;
                let tmp1 = b0_2;
                b0_1 = src[idx0 + x + 1];
                b0_2 = src[idx0 + x + 1 + sstride];
                let mut p0 =  tmp0                       << 4;
                let mut p1 = (tmp0 + b0_1)               << 3;
                let mut p2 = (tmp0 + tmp1)               << 3;
                let mut p3 = (tmp0 + tmp1 + b0_1 + b0_2) << 2;

                let tmp0 = b1_1;
                let tmp1 = b1_2;
                let tmp2 = filt_lo(tmp0, tmp1);
                let tmp3 = filt_hi(tmp0, tmp1, b1_3);
                b1_2 = src[ idx1 + x + 1];
                b1_1 = src[bidx1 + x + 1];
                b1_3 = filt_hi(b1_1, b1_2, src[idx1 + x + 1 + sstride]);
                p0 +=  tmp2                << 3;
                p1 += (tmp2 + b1_1 + b1_2) << 2;
                p2 +=  tmp3                << 2;
                p3 += (tmp3 + b1_3)        << 1;

                b2_3 = src[idx2 + x + 1];
                b2_6 = src[idx2 + x + 1 + sstride];
                let tmp0 = filt_lo(b2_1, b2_2);
                let tmp1 = filt_hi(b2_1, b2_2, b2_3);
                p0 +=  tmp0                              << 3;
                p1 +=  tmp1                              << 2;
                p2 += (tmp0 + filt_lo(b2_4, b2_5))       << 2;
                p3 += (tmp1 + filt_hi(b2_4, b2_5, b2_6)) << 1;

                b3_6 = src[idx3 + x + 1];
                b3_3 = src[bidx3 + x + 1];
                b3_9 = filt_hi(b3_3, b3_6, src[idx3 + x + 1 + sstride]);
                let tmp0 = b3_1 + b3_4;
                let tmp1 = b3_2 + b3_5;
                let tmp2 = b3_3 + b3_6;
                p0 += filt_lo(tmp0, tmp1)       << 2;
                p1 += filt_hi(tmp0, tmp1, tmp2) << 1;
                p2 += filt_lo(b3_7, b3_8)       << 1;
                p3 += filt_hi(b3_7, b3_8, b3_9) << 0;

                dst[oidx0 + x * 2 + 0] = clip8((p0 >> 6) + 128);
                dst[oidx0 + x * 2 + 1] = clip8((p1 >> 6) + 128);
                dst[oidx1 + x * 2 + 0] = clip8((p2 >> 6) + 128);
                dst[oidx1 + x * 2 + 1] = clip8((p3 >> 6) + 128);
            }
            bidx1 = idx1;
            bidx3 = idx3;
            idx0 += sstride;
            idx1 += sstride;
            idx2 += sstride;
            idx3 += sstride;
            oidx0 += dstride * 2;
            oidx1 += dstride * 2;
        }
    }
}
