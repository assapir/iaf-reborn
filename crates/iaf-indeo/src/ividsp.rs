// Ported from NihAV (https://nihav.org, git.nihav.org nihav.git, commit 7552f86), © Kostya Shishkov, AGPL-3.0-or-later.
use crate::ivi::{IVITransformType,TDir,TrFunc,TrFuncDC};

#[inline(always)]
fn hbutterfly(a: i32, b: i32) -> (i32, i32) {
    ((a + b) >> 1, (a - b) >> 1)
}
#[inline(always)]
fn butterfly(a: i32, b: i32) -> (i32, i32) {
    (a + b, a - b)
}
#[inline(always)]
fn ireflect(a: i32, b: i32) -> (i32, i32) {
    (((b * 2 - a + 2) >> 2) - a, ((b + 2 * a + 2) >> 2) + b)
}

macro_rules! haar_transform {
    ($c0:expr, $c1:expr, $c2:expr, $c3:expr) => {{
        let (t0, t1) = hbutterfly($c0, $c1);
        let (t2, t3) = hbutterfly(t0,  $c2);
        $c0 = t2;
        $c1 = t3;
        let (t4, t5) = hbutterfly(t1,  $c3);
        $c2 = t4;
        $c3 = t5;
    }};
    ($c0:expr, $c1:expr, $c2:expr, $c3:expr, $c4:expr, $c5:expr, $c6:expr, $c7:expr) => {{
        let (a0, a1) = hbutterfly($c0 << 1, $c1 << 1);

        let (t0, t1) = hbutterfly(a0, $c2);
        let (t2, t3) = hbutterfly(a1, $c3);
        let (u0, u1) = hbutterfly(t0, $c4);
        let (u2, u3) = hbutterfly(t1, $c5);
        let (u4, u5) = hbutterfly(t2, $c6);
        let (u6, u7) = hbutterfly(t3, $c7);

        $c0 = u0;
        $c1 = u1;
        $c2 = u2;
        $c3 = u3;
        $c4 = u4;
        $c5 = u5;
        $c6 = u6;
        $c7 = u7;
    }};
}
macro_rules! slant_transform {
    ($c0:expr, $c1:expr, $c2:expr, $c3:expr, $output:ident) => {{
        let (t0, t1) = butterfly($c0, $c2);
        let (t2, t3) = ireflect ($c3, $c1);
        let (t4, t5) = butterfly(t0,  t3);
        let (t6, t7) = butterfly(t1,  t2);
        $c0 = $output(t4);
        $c1 = $output(t6);
        $c2 = $output(t7);
        $c3 = $output(t5);
    }};
    ($c0:expr, $c1:expr, $c2:expr, $c3:expr, $c4:expr, $c5:expr, $c6:expr, $c7:expr, $output:ident) => {{
        let t0 = $c3 + (($c1 * 4 -  $c3 + 4) >> 3);
        let t1 = $c1 + ((-$c1 - $c3 * 4 + 4) >> 3);

        let (t2, t3) = butterfly($c0, t1);
        let (t4, t5) = butterfly($c4, $c5);
        let (t6, t7) = butterfly($c7, $c6);
        let (t8, t9) = butterfly(t0,  $c2);

        let (u0, u1) = butterfly(t2, t4);
        let (u2, u3) = ireflect (t7, t8);
        let (u4, u5) = butterfly(t3, t5);
        let (u6, u7) = ireflect (t6, t9);

        let (t0, t1) = butterfly(u0, u3);
        let (t2, t3) = butterfly(u1, u2);
        let (t4, t5) = butterfly(u4, u7);
        let (t6, t7) = butterfly(u5, u6);

        $c0 = $output(t0);
        $c1 = $output(t2);
        $c2 = $output(t3);
        $c3 = $output(t1);
        $c4 = $output(t4);
        $c5 = $output(t6);
        $c6 = $output(t7);
        $c7 = $output(t5);
    }};
}

fn haar8x8_2d(blk: &mut[i32; 64]) {
    for i in 0..4 {
        let mut c0 = blk[i + 0*8] << 1;
        let mut c1 = blk[i + 1*8] << 1;
        let mut c2 = blk[i + 2*8] << 1;
        let mut c3 = blk[i + 3*8] << 1;
        haar_transform!(c0, c1, c2, c3,
                        blk[i + 4*8], blk[i + 5*8], blk[i + 6*8], blk[i + 7*8]);
        blk[i + 0*8] = c0;
        blk[i + 1*8] = c1;
        blk[i + 2*8] = c2;
        blk[i + 3*8] = c3;
    }
    for i in 4..8 {
        haar_transform!(blk[i + 0*8], blk[i + 1*8], blk[i + 2*8], blk[i + 3*8],
                        blk[i + 4*8], blk[i + 5*8], blk[i + 6*8], blk[i + 7*8]);
    }
    for i in 0..8 {
        let row = &mut blk[i*8..(i+1)*8];
        haar_transform!(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7]);
    }
}
fn haar8x8_row(blk: &mut[i32; 64]) {
    for i in 0..8 {
        let row = &mut blk[i*8..(i+1)*8];
        haar_transform!(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7]);
    }
}
fn haar8x8_col(blk: &mut[i32; 64]) {
    for i in 0..8 {
        haar_transform!(blk[i + 0*8], blk[i + 1*8], blk[i + 2*8], blk[i + 3*8],
                        blk[i + 4*8], blk[i + 5*8], blk[i + 6*8], blk[i + 7*8]);
    }
}
fn haar8x8_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = in0 >> 3;
    for el in blk.iter_mut() { *el = dc; }
}

fn haar4x4_2d(blk: &mut[i32; 64]) {
    for i in 0..2 {
        let mut c0 = blk[i + 0*4] << 1;
        let mut c1 = blk[i + 1*4] << 1;
        haar_transform!(c0, c1, blk[i + 2*4], blk[i + 3*4]);
        blk[i + 0*4] = c0;
        blk[i + 1*4] = c1;
    }
    for i in 2..4 {
        haar_transform!(blk[i + 0*4], blk[i + 1*4], blk[i + 2*4], blk[i + 3*4]);
    }
    for i in 0..4 {
        let row = &mut blk[i*4..(i+1)*4];
        haar_transform!(row[0], row[1], row[2], row[3]);
    }
}
fn haar4x4_row(blk: &mut[i32; 64]) {
    for i in 0..4 {
        let row = &mut blk[i*4..(i+1)*4];
        haar_transform!(row[0], row[1], row[2], row[3]);
    }
}
fn haar4x4_col(blk: &mut[i32; 64]) {
    for i in 0..4 {
        haar_transform!(blk[i + 0*4], blk[i + 1*4], blk[i + 2*4], blk[i + 3*4]);
    }
}
fn haar4x4_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = in0 >> 3;
    for el in blk[..16].iter_mut() { *el = dc; }
}

fn slant8x8_2d(blk: &mut[i32; 64]) {
    let pass1 = |x: i32| x;
    let pass2 = |x: i32| (x + 1) >> 1;

    for i in 0..8 {
        let mut s0 = 0;
        for j in 0..8 { s0 |= blk[i + j*8]; }
        if s0 == 0 { continue; }

        slant_transform!(blk[i + 0*8], blk[i + 1*8], blk[i + 2*8], blk[i + 3*8],
                         blk[i + 4*8], blk[i + 5*8], blk[i + 6*8], blk[i + 7*8], pass1);
    }
    for i in 0..8 {
        let row = &mut blk[i*8..(i+1)*8];
        slant_transform!(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], pass2);
    }
}
fn slant8x8_2d_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = (in0 + 1) >> 1;
    for el in blk.iter_mut() { *el = dc; }
}
fn slant8x8_row(blk: &mut[i32; 64]) {
    let pass = |x: i32| (x + 1) >> 1;

    for i in 0..8 {
        let row = &mut blk[i*8..(i+1)*8];
        slant_transform!(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], pass);
    }
}
fn slant8x8_row_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = (in0 + 1) >> 1;

    for el in blk[0..8].iter_mut() { *el = dc; }
    for el in blk[8..].iter_mut()  { *el = 0; }
}
fn slant8x8_col(blk: &mut[i32; 64]) {
    let pass = |x: i32| (x + 1) >> 1;

    for i in 0..8 {
        slant_transform!(blk[i + 0*8], blk[i + 1*8], blk[i + 2*8], blk[i + 3*8],
                         blk[i + 4*8], blk[i + 5*8], blk[i + 6*8], blk[i + 7*8], pass);
    }
}
fn slant8x8_col_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = (in0 + 1) >> 1;

    for i in 0..8 {
        blk[i * 8] = dc;
        for j in 1..8 { blk[i * 8 + j] = 0; }
    }
}

fn slant4x4_2d(blk: &mut[i32; 64]) {
    let pass1 = |x: i32| x;
    let pass2 = |x: i32| (x + 1) >> 1;

    for i in 0..4 {
        slant_transform!(blk[i + 0*4], blk[i + 1*4], blk[i + 2*4], blk[i + 3*4], pass1);
    }
    for i in 0..4 {
        let row = &mut blk[i*4..(i+1)*4];
        slant_transform!(row[0], row[1], row[2], row[3], pass2);
    }
}
fn slant4x4_2d_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = (in0 + 1) >> 1;
    for el in blk[..16].iter_mut() { *el = dc; }
}
fn slant4x4_row(blk: &mut[i32; 64]) {
    let pass = |x: i32| (x + 1) >> 1;

    for i in 0..4 {
        let row = &mut blk[i*4..(i+1)*4];
        slant_transform!(row[0], row[1], row[2], row[3], pass);
    }
}
fn slant4x4_row_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = (in0 + 1) >> 1;

    for el in blk[0..4].iter_mut()  { *el = dc; }
    for el in blk[4..16].iter_mut() { *el = 0; }
}
fn slant4x4_col(blk: &mut[i32; 64]) {
    let pass = |x: i32| (x + 1) >> 1;

    for i in 0..4 {
        slant_transform!(blk[i + 0*4], blk[i + 1*4], blk[i + 2*4], blk[i + 3*4], pass);
    }
}
fn slant4x4_col_dc(blk: &mut[i32; 64], in0: i32) {
    let dc = (in0 + 1) >> 1;

    for i in 0..4 {
        blk[i * 4] = dc;
        for j in 1..4 { blk[i * 4 + j] = 0; }
    }
}

fn none8x8(_blk: &mut[i32; 64]) {
}
fn none8x8_dc(blk: &mut[i32; 64], dc: i32) {
    for el in blk[1..8].iter_mut() { *el = dc; }
    for el in blk[8..].iter_mut()  { *el = 0; }
}
fn none4x4(_blk: &mut[i32; 64]) {
}
fn none4x4_dc(blk: &mut[i32; 64], dc: i32) {
    for el in blk[1..4].iter_mut()  { *el = dc; }
    for el in blk[4..16].iter_mut() { *el = 0; }
}

pub fn ivi_get_transform8x8_funcs(ttype: IVITransformType) -> (TrFunc, TrFuncDC) {
    match ttype {
        IVITransformType::Haar(_, ref dir) => {
            match *dir {
                TDir::TwoD => { (haar8x8_2d,  haar8x8_dc) },
                TDir::Row  => { (haar8x8_row, haar8x8_dc) },
                TDir::Col  => { (haar8x8_col, haar8x8_dc) },
            } },
        IVITransformType::Slant(_, ref dir) => {
            match *dir {
                TDir::TwoD => { (slant8x8_2d,  slant8x8_2d_dc) },
                TDir::Row  => { (slant8x8_row, slant8x8_row_dc) },
                TDir::Col  => { (slant8x8_col, slant8x8_col_dc) },
            } },
        IVITransformType::None(_) => { (none8x8, none8x8_dc) }
    }
}
pub fn ivi_get_transform4x4_funcs(ttype: IVITransformType) -> (TrFunc, TrFuncDC) {
    match ttype {
        IVITransformType::Haar(_, ref dir) => {
            match *dir {
                TDir::TwoD => { (haar4x4_2d,  haar4x4_dc) },
                TDir::Row  => { (haar4x4_row, haar4x4_dc) },
                TDir::Col  => { (haar4x4_col, haar4x4_dc) },
            } },
        IVITransformType::Slant(_, ref dir) => {
            match *dir {
                TDir::TwoD => { (slant4x4_2d,  slant4x4_2d_dc) },
                TDir::Row  => { (slant4x4_row, slant4x4_row_dc) },
                TDir::Col  => { (slant4x4_col, slant4x4_col_dc) },
            } },
        IVITransformType::None(_) => { (none4x4, none4x4_dc) }
    }
}

pub fn ivi_mc_put(dst: &mut [i16], dstride: usize, src: &[i16], sstride: usize, mode: u8, w: usize, h: usize) {
    if src.len() < w + h * sstride { return; }
    match mode {
        0 => {
            for (dline, sline) in dst.chunks_mut(dstride).zip(src.chunks(sstride)).take(h) {
                dline[..w].copy_from_slice(&sline[..w]);
            }
        },
        1 => {
            for (dline, sline) in dst.chunks_mut(dstride).zip(src.chunks(sstride)).take(h) {
                for (dpix, pair) in dline.iter_mut().zip(sline.windows(2)).take(w) {
                    *dpix = (pair[0] + pair[1]) >> 1;
                }
            }
        },
        2 => {
            for (dline, (sline0, sline1)) in dst.chunks_mut(dstride)
                    .zip(src.chunks(sstride).zip(src.chunks(sstride).skip(1))).take(h) {
                for (dpix, (&s0, &s1)) in dline.iter_mut().zip(sline0.iter().zip(sline1.iter())).take(w) {
                    *dpix = (s0 + s1) >> 1;
                }
            }
        },
        3 => {
            for (dline, (sline0, sline1)) in dst.chunks_mut(dstride)
                    .zip(src.chunks(sstride).zip(src.chunks(sstride).skip(1))).take(h) {
                for (dpix, (pair0, pair1)) in dline.iter_mut()
                        .zip(sline0.windows(2).zip(sline1.windows(2))).take(w) {
                    *dpix = (pair0[0] + pair0[1] + pair1[0] + pair1[1]) >> 2;
                }
            }
        },
        _ => {},
    }
}
