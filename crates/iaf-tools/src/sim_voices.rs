//! `iaf-sim voices`: Modern IAF's speech clips (modern-iaf/docs/sound.md §5). Kokoro text to speech says each line of
//! `modern-iaf/data/sounds/voices.json` as a whole phrase (`tools/iaf-2026/kokoro_tts.py`, the one Python step); this
//! module trims it, runs Betty's chain or the radio chain on it and writes the clip as Ogg Vorbis (ffmpeg) into
//! `<data>/sounds`, the clips the repository ships; then `sim::own_sounds` compiles them into the assets.
//! Every click and noise is computed here and seeded, so a run is repeatable up to Kokoro's own output.

use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};

use crate::log;
use crate::progress::{Progress, check};

/// Kokoro's sample rate; ffmpeg resamples to `sim::SOUND_RATE` as it encodes.
pub const SR: f32 = 24000.0;
/// The Kokoro step, run by `IAF_KOKORO_PYTHON` (default `python3`).
pub const KOKORO: &str = "tools/iaf-2026/kokoro_tts.py";
/// libvorbis quality: about 45 kbit/s for 22050 Hz mono speech.
const OGG_Q: &str = "4";

/// Betty's chain (sound.md §5.1): high-pass, a presence peak, a hard compressor, a loud level, the call said twice.
pub struct Betty {
    /// The pitch raise over Kokoro's voice.
    pub semitones: f32,
    pub highpass_hz: f32,
    pub lowpass_hz: f32,
    pub presence_hz: f32,
    pub presence_db: f32,
    pub threshold_db: f32,
    pub ratio: f32,
    pub vrms_db: f32,
    /// Seconds of silence between the repeats.
    pub gap: f32,
}

pub const BETTY: Betty = Betty {
    semitones: 3.0,
    highpass_hz: 250.0,
    lowpass_hz: 4000.0,
    presence_hz: 2500.0,
    presence_db: 5.0,
    threshold_db: -26.0,
    ratio: 8.0,
    vrms_db: -13.0,
    gap: 0.2,
};

/// The radio chain (sound.md §5.2): band-pass, compressor, a little drive, the level, hiss, and for a whole
/// transmission the key-on and key-off clicks.
pub struct Radio {
    pub band: (f32, f32),
    pub threshold_db: f32,
    pub ratio: f32,
    pub drive: f32,
    pub mix: f32,
    pub vrms_db: f32,
    pub hiss_db: f32,
    /// The microphone's pre-emphasis, x[n] - k x[n-1].
    pub emphasis: f32,
    /// A low-mid peak at 500 Hz (Q 0.9), dB: the in-helmet mic's chest.
    pub low_mid_db: f32,
}

pub const RADIO: Radio = Radio {
    band: (300.0, 3000.0),
    threshold_db: -24.0,
    ratio: 4.0,
    drive: 2.5,
    mix: 0.3,
    vrms_db: -17.9, // 0.127: the level of shared/extra/tower_numbers, which match the original speech
    hiss_db: -42.0,
    emphasis: 0.9,
    low_mid_db: 0.0,
};

/// The player's own calls (`Mode::Helmet`, approved 2026-11-12, item A21): the radio chain heard from an oxygen-mask
/// microphone inside the helmet: more low-mid, less air (a lower band top, a softer pre-emphasis). Inferred values.
pub const HELMET: Radio = Radio { band: (300.0, 2600.0), emphasis: 0.75, low_mid_db: 4.0, ..RADIO };

/// Seconds from the player's call's key-off to the tower's key-on (`radio_gap.ogg`; inferred: a controller's reply,
/// approved with item A21).
pub const RADIO_GAP: f32 = 0.6;

const PEAK: f32 = 0.79; // the soft limit, -2 dBFS
const SEED: u64 = 2026;

/// One second-order section (the RBJ cookbook's filters), run in direct form I.
#[derive(Clone, Copy)]
struct Biquad {
    b: [f32; 3],
    a: [f32; 2],
}

impl Biquad {
    fn new(b: [f32; 3], a: [f32; 3]) -> Self {
        Biquad { b: b.map(|v| v / a[0]), a: [a[1] / a[0], a[2] / a[0]] }
    }
    fn w(f: f32, q: f32) -> (f32, f32) {
        let w = std::f32::consts::TAU * f / SR;
        (w.cos(), w.sin() / (2.0 * q))
    }
    fn lowpass(f: f32, q: f32) -> Self {
        let (c, al) = Self::w(f, q);
        Self::new([(1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0], [1.0 + al, -2.0 * c, 1.0 - al])
    }
    fn highpass(f: f32, q: f32) -> Self {
        let (c, al) = Self::w(f, q);
        Self::new([(1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0], [1.0 + al, -2.0 * c, 1.0 - al])
    }
    fn peak(f: f32, q: f32, db: f32) -> Self {
        let (c, al) = Self::w(f, q);
        let a = 10f32.powf(db / 40.0);
        Self::new([1.0 + al * a, -2.0 * c, 1.0 - al * a], [1.0 + al / a, -2.0 * c, 1.0 - al / a])
    }
    fn run(&self, x: &mut [f32]) {
        let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
        for v in x {
            let y = self.b[0] * *v + self.b[1] * x1 + self.b[2] * x2 - self.a[0] * y1 - self.a[1] * y2;
            (x2, x1, y2, y1) = (x1, *v, y1, y);
            *v = y;
        }
    }
}

/// The two sections' Q of a 4th-order Butterworth filter.
const BUTTER4: [f32; 2] = [0.541_196_1, 1.306_563];

/// 4th-order Butterworth high-pass at `lo` and low-pass at `hi`.
fn band(x: &mut [f32], lo: f32, hi: f32) {
    for q in BUTTER4 {
        Biquad::highpass(lo, q).run(x);
        Biquad::lowpass(hi, q).run(x);
    }
}

/// A feed-forward compressor on the peak envelope: above `threshold_db` the level rises by 1/`ratio`.
fn compress(x: &mut [f32], threshold_db: f32, ratio: f32, attack_s: f32, release_s: f32) {
    let (ga, gr) = ((-1.0 / (attack_s * SR)).exp(), (-1.0 / (release_s * SR)).exp());
    let mut env = 0f32;
    for v in x {
        let g = if v.abs() > env { ga } else { gr };
        env = g * env + (1.0 - g) * v.abs();
        let over = 20.0 * env.max(1e-6).log10() - threshold_db;
        if over > 0.0 {
            *v *= 10f32.powf(-over * (1.0 - 1.0 / ratio) / 20.0);
        }
    }
}

fn peak(x: &[f32]) -> f32 {
    x.iter().fold(0f32, |m, v| m.max(v.abs()))
}

/// The RMS of the samples above 2 % of the peak (the pauses left out): sound.md's vrms.
pub fn vrms(x: &[f32]) -> f32 {
    let p = 0.02 * peak(x);
    let v: Vec<f32> = x.iter().copied().filter(|v| v.abs() > p).collect();
    (v.iter().map(|v| v * v).sum::<f32>() / v.len().max(1) as f32).sqrt()
}

/// The voiced RMS to `vrms_db` with a soft limit at PEAK, repeated until both hold.
fn level(x: &mut [f32], vrms_db: f32) {
    let target = 10f32.powf(vrms_db / 20.0);
    for _ in 0..4 {
        let k = target / vrms(x).max(1e-9);
        x.iter_mut().for_each(|v| *v = PEAK * (*v * k / PEAK).tanh());
    }
}

/// The voiced RMS to `vrms_db` by a plain gain.
fn gain_to(x: &mut [f32], vrms_db: f32) {
    let k = 10f32.powf(vrms_db / 20.0) / vrms(x).max(1e-9);
    x.iter_mut().for_each(|v| *v *= k);
}

/// A slight distortion: the peak to 1, `mix` of it through tanh(`drive` x).
fn drive(x: &mut [f32], drive: f32, mix: f32) {
    let p = peak(x).max(1e-9);
    x.iter_mut().for_each(|v| *v = (1.0 - mix) * *v / p + mix * (drive * *v / p).tanh() / drive.tanh());
}

/// The clip between the first and last sample above `rel` of the peak, 10 ms margin each side.
fn trim(x: &[f32], rel: f32) -> Vec<f32> {
    let p = rel * peak(x);
    let (Some(a), Some(b)) = (x.iter().position(|v| v.abs() > p), x.iter().rposition(|v| v.abs() > p)) else {
        return x.to_vec();
    };
    let m = (SR / 100.0) as usize;
    x[a.saturating_sub(m)..(b + m).min(x.len())].to_vec()
}

/// Linear fades of `a` and `b` seconds at the ends.
fn fade(x: &mut [f32], a: f32, b: f32) {
    let n = x.len();
    let (na, nb) = (((a * SR) as usize).min(n), ((b * SR) as usize).min(n));
    (0..na).for_each(|i| x[i] *= i as f32 / na as f32);
    (0..nb).for_each(|i| x[n - 1 - i] *= i as f32 / nb as f32);
}

fn silence(s: f32) -> Vec<f32> {
    vec![0.0; (s * SR) as usize]
}

/// Seeded noise (xorshift64*, four uniforms summed: near Gaussian).
pub struct Noise(pub u64);

impl Noise {
    fn next(&mut self) -> f32 {
        let mut s = 0.0;
        for _ in 0..4 {
            self.0 ^= self.0 >> 12;
            self.0 ^= self.0 << 25;
            self.0 ^= self.0 >> 27;
            s += (self.0.wrapping_mul(0x2545_f491_4f6c_dd1d) >> 40) as f32 / (1u64 << 24) as f32;
        }
        (s - 2.0) * 1.732
    }
    /// `s` seconds of radio-band hiss at an RMS of `db`.
    fn hiss(&mut self, s: f32, db: f32) -> Vec<f32> {
        let mut w: Vec<f32> = (0..(s * SR) as usize).map(|_| self.next()).collect();
        band(&mut w, RADIO.band.0, RADIO.band.1);
        let rms = (w.iter().map(|v| v * v).sum::<f32>() / w.len().max(1) as f32).sqrt().max(1e-9);
        let k = 10f32.powf(db / 20.0) / rms;
        w.iter_mut().for_each(|v| *v *= k);
        w
    }
    /// The press-to-talk switch: a 2 ms broadband tick under a Hann window.
    fn click(&mut self) -> Vec<f32> {
        let n = (0.002 * SR) as usize;
        (0..n).map(|i| self.next() * 0.25 * (std::f32::consts::PI * i as f32 / n as f32).sin().powi(2)).collect()
    }
    /// Key-on, the receiver's squelch opening: a beat of quiet, the click, then a beat of carrier hiss before the
    /// voice (KEY times, sound.md §5.2).
    pub fn key_on(&mut self) -> Vec<f32> {
        [silence(KEY.quiet_before), self.click(), self.hiss(KEY.lead, RADIO.hiss_db)].concat()
    }
    /// Key-off, the squelch closing: a beat of carrier hiss after the voice, the squelch's noise burst falling
    /// away, the click, then a beat of quiet.
    pub fn key_off(&mut self) -> Vec<f32> {
        let mut burst = self.hiss(KEY.burst, -24.0);
        let n = burst.len() as f32;
        burst.iter_mut().enumerate().for_each(|(i, v)| *v *= 1.0 - 0.7 * i as f32 / n);
        [self.hiss(KEY.tail, RADIO.hiss_db), burst, self.click(), silence(KEY.quiet_after)].concat()
    }
}

/// The timing of a keyed transmission, in seconds. `lead` and `tail` are the carrier hiss between the squelch and
/// the voice, from a tower frequency recorded on a scanner (sound.md §5.2: the voice starts a median 60 ms, upper
/// quartile 120 ms, after the squelch opens and ends a median 150 ms, quartiles 95-230 ms, before it closes).
pub struct Key {
    pub quiet_before: f32,
    pub lead: f32,
    pub tail: f32,
    pub burst: f32,
    pub quiet_after: f32,
}

pub const KEY: Key = Key { quiet_before: 0.1, lead: 0.15, tail: 0.15, burst: 0.08, quiet_after: 0.2 };

/// How a clip is made (voices.json `mode`).
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Mode {
    /// The cockpit's warning voice: Betty's chain, said `repeat` times.
    Betty,
    /// A whole transmission in one clip: the radio chain with key-on and key-off.
    Radio,
    /// A part of a tower call (or the whole call), which radio.gd plays back to back with others and frames with the
    /// key clicks: the radio chain and hiss, no clicks.
    Phrase,
    /// A part of the player's own call: the [`HELMET`] chain and hiss, no clicks (radio.gd frames the call).
    Helmet,
}

impl Mode {
    fn of(s: &str) -> Result<Self> {
        Ok(match s {
            "betty" => Mode::Betty,
            "radio" => Mode::Radio,
            "helmet" => Mode::Helmet,
            "phrase" | "particle" => Mode::Phrase,
            m => bail!("voices: mode \"{m}\" is not betty / radio / helmet / phrase / particle"),
        })
    }
}

/// Betty's chain on Kokoro's speech `x`.
pub fn betty(x: &[f32], c: &Betty, repeat: usize) -> Vec<f32> {
    let mut x = trim(x, 0.02);
    for q in BUTTER4 {
        Biquad::highpass(c.highpass_hz, q).run(&mut x);
        Biquad::lowpass(c.lowpass_hz, q).run(&mut x);
    }
    Biquad::peak(c.presence_hz, 0.7, c.presence_db).run(&mut x);
    let p = peak(&x).max(1e-9);
    x.iter_mut().for_each(|v| *v *= 0.5 / p);
    compress(&mut x, c.threshold_db, c.ratio, 0.002, 0.06);
    level(&mut x, c.vrms_db);
    // The limiter's harmonics filtered off again, the level kept.
    for q in BUTTER4 {
        Biquad::lowpass(c.lowpass_hz, q).run(&mut x);
    }
    gain_to(&mut x, c.vrms_db);
    fade(&mut x, 0.003, 0.01);
    let pad = silence(0.01);
    let one = [pad.clone(), x, pad].concat();
    let mut out = one.clone();
    for _ in 1..repeat {
        out.extend(silence(c.gap - 0.02));
        out.extend(&one);
    }
    out
}

/// The radio chain on Kokoro's speech `x`.
pub fn radio(x: &[f32], mode: Mode, noise: &mut Noise) -> Vec<f32> {
    let c = if mode == Mode::Helmet { &HELMET } else { &RADIO };
    let mut x = trim(x, 0.01);
    x = [vec![x[0]], x.windows(2).map(|w| w[1] - c.emphasis * w[0]).collect()].concat(); // a headset mic's presence lift
    drive(&mut x, c.drive, c.mix);
    band(&mut x, c.band.0, c.band.1);
    if c.low_mid_db != 0.0 {
        Biquad::peak(500.0, 0.9, c.low_mid_db).run(&mut x);
    }
    let p = peak(&x).max(1e-9);
    x.iter_mut().for_each(|v| *v *= 0.5 / p);
    compress(&mut x, c.threshold_db, c.ratio, 0.005, 0.08);
    level(&mut x, c.vrms_db);
    band(&mut x, c.band.0, c.band.1); // the limiter's harmonics filtered off again: 8th order in all
    gain_to(&mut x, c.vrms_db);
    fade(&mut x, 0.005, 0.02);
    let pad = silence(0.01);
    let mut x = [pad.clone(), x, pad].concat();
    let hiss = noise.hiss(x.len() as f32 / SR, c.hiss_db);
    x.iter_mut().zip(hiss).for_each(|(v, h)| *v += h);
    if mode == Mode::Radio {
        x = [noise.key_on(), x, noise.key_off()].concat();
    }
    x
}

/// The head (up to the word before the ";") or the tail (from the word after it) of a sentence, at Kokoro's word
/// timing `split` = [end of the word before, start of the word after] in seconds, with 30 ms to spare.
fn cut(x: &[f32], part: &str, split: [f32; 2]) -> Result<Vec<f32>> {
    let at = |s: f32| ((s * SR) as usize).min(x.len());
    Ok(match part {
        "head" => x[..at(split[0] + 0.03)].to_vec(),
        "tail" => x[at((split[1] - 0.03).max(0.0))..].to_vec(),
        p => bail!("voices: cut \"{p}\" is not head / tail"),
    })
}

/// A mono 32-bit float WAV's samples (kokoro_tts.py's).
fn read_wav(bytes: &[u8]) -> Result<Vec<f32>> {
    ensure!(bytes.len() > 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WAVE", "not a WAV");
    let (mut i, mut fmt) = (12, None);
    while i + 8 <= bytes.len() {
        let len = u32::from_le_bytes(bytes[i + 4..i + 8].try_into()?) as usize;
        let body = bytes.get(i + 8..i + 8 + len).context("a short WAV chunk")?;
        match &bytes[i..i + 4] {
            b"fmt " => fmt = Some((u16::from_le_bytes([body[0], body[1]]), u16::from_le_bytes([body[2], body[3]]))),
            b"data" => {
                ensure!(fmt == Some((3, 1)), "WAV format {fmt:?}, not mono 32-bit float");
                return Ok(body.as_chunks::<4>().0.iter().map(|c| f32::from_le_bytes(*c)).collect());
            }
            _ => {}
        }
        i += 8 + len + (len & 1);
    }
    bail!("WAV without data")
}

/// `x` (at SR) through ffmpeg with the output options `opts` into `out` (raw 32-bit float in).
fn ffmpeg(x: &[f32], opts: &[&str], out: &Path, tmp: &Path) -> Result<()> {
    let raw = tmp.join("in.f32");
    std::fs::write(&raw, x.iter().flat_map(|v| v.to_le_bytes()).collect::<Vec<u8>>())?;
    let st = Command::new("ffmpeg")
        .args(["-v", "error", "-y", "-f", "f32le", "-ar", &(SR as u32).to_string(), "-ac", "1", "-i"])
        .arg(&raw)
        .args(opts)
        .arg(out)
        .status()
        .context("ffmpeg (with libvorbis and rubberband) is needed to make the clips")?;
    ensure!(st.success(), "ffmpeg failed on {}", out.display());
    Ok(())
}

/// `x` (at SR) as 22050 Hz mono Ogg Vorbis at `out`.
pub fn write_ogg(x: &[f32], out: &Path, tmp: &Path) -> Result<()> {
    let rate = crate::sim::SOUND_RATE.to_string();
    let x: Vec<f32> = x.iter().map(|v| v.clamp(-1.0, 1.0)).collect();
    ffmpeg(&x, &["-ar", &rate, "-ac", "1", "-c:a", "libvorbis", "-q:a", OGG_Q], out, tmp)
}

/// `x` `semitones` higher with its formants kept (ffmpeg's rubberband): a higher voice, not a chipmunk.
fn pitch(x: &[f32], semitones: f32, tmp: &Path) -> Result<Vec<f32>> {
    let out = tmp.join("pitch.f32");
    let af = format!("rubberband=pitch={:.4}:formant=preserved", 2f32.powf(semitones / 12.0));
    ffmpeg(x, &["-af", &af, "-f", "f32le", "-ac", "1"], &out, tmp)?;
    Ok(std::fs::read(&out)?.as_chunks::<4>().0.iter().map(|c| f32::from_le_bytes(*c)).collect())
}

/// Kokoro's speech of a line and its ";" split times ([`kokoro`]).
pub type Said = (Vec<f32>, Option<[f32; 2]>);

/// One line for Kokoro.
pub struct Line {
    pub text: String,
    pub voice: String,
    pub speed: f64,
}

/// Kokoro's speech of each line, with the ";" split times where the line has one (kokoro_tts.py).
pub fn kokoro(repo: &Path, lines: &[Line], tmp: &Path) -> Result<Vec<Said>> {
    let python = std::env::var("IAF_KOKORO_PYTHON").unwrap_or_else(|_| "python3".into());
    let req: Vec<Value> = lines
        .iter()
        .enumerate()
        .map(|(i, l)| {
            let out = tmp.join(format!("raw{i}.wav"));
            json!({"text": l.text, "voice": l.voice, "speed": l.speed, "out": out})
        })
        .collect();
    let mut child = Command::new(&python)
        .arg("-I")
        .arg(repo.join(KOKORO))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .with_context(|| format!("{python} {KOKORO} (Kokoro: see its header for the setup)"))?;
    child.stdin.take().context("stdin")?.write_all(serde_json::to_string(&req)?.as_bytes())?;
    let out = child.wait_with_output()?;
    ensure!(out.status.success(), "{KOKORO} failed");
    let done: Vec<Value> = serde_json::from_slice(&out.stdout).context("kokoro_tts.py's answer")?;
    ensure!(done.len() == lines.len(), "kokoro_tts.py answered {} of {} lines", done.len(), lines.len());
    done.iter()
        .map(|d| {
            let path = PathBuf::from(d["out"].as_str().context("out")?);
            let x = read_wav(&std::fs::read(&path)?).with_context(|| path.display().to_string())?;
            let split = d["split"]
                .as_array()
                .map(|a| [a[0].as_f64().unwrap_or(0.0) as f32, a[1].as_f64().unwrap_or(0.0) as f32]);
            Ok((x, split))
        })
        .collect()
}

/// A scratch folder removed on drop.
struct Tmp(PathBuf);

impl Drop for Tmp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn tmp_dir() -> Result<Tmp> {
    let d = std::env::temp_dir().join(format!("iaf-sim-voices-{}", std::process::id()));
    std::fs::create_dir_all(&d)?;
    Ok(Tmp(d))
}

fn role<'a>(v: &'a Value, name: &str) -> Result<(&'a str, f64)> {
    let r = &v["voices"][name];
    let voice = r["model"].as_str().with_context(|| format!("voices.json: no voice \"{name}\""))?;
    Ok((voice, r["speed"].as_f64().unwrap_or(1.0)))
}

/// One clip of the voice set: Kokoro's speech made into the clip of `mode`.
fn make(x: &[f32], split: Option<[f32; 2]>, c: &Value, mode: Mode, noise: &mut Noise, tmp: &Path) -> Result<Vec<f32>> {
    match mode {
        Mode::Betty => Ok(betty(&pitch(x, BETTY.semitones, tmp)?, &BETTY, c["repeat"].as_u64().unwrap_or(1) as usize)),
        _ => {
            let x = match c["cut"].as_str() {
                Some(part) => cut(x, part, split.with_context(|| format!("{}: no \";\" to cut at", c["say"]))?)?,
                None => x.to_vec(),
            };
            Ok(radio(&x, mode, noise))
        }
    }
}

/// `iaf-sim voices`: every clip of `<data>/sounds/voices.json` (`only`: the clips whose file name contains it) into
/// `<data>/sounds`, the computed `kch2.ogg`, `twr_pause.ogg`, `key_on.ogg`, `key_off.ogg` and `radio_gap.ogg`, then
/// `sim::own_sounds` into `assets`.
pub fn voices(
    data: &Path,
    repo: &Path,
    assets: &Path,
    only: Option<&str>,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    let sounds = data.join("sounds");
    let v: Value = serde_json::from_str(&std::fs::read_to_string(sounds.join("voices.json"))?)?;
    let tmp = tmp_dir()?;
    let mut noise = Noise(SEED);
    let computed = [
        ("kch2.ogg", [silence(0.01), noise.key_off()].concat()),
        ("twr_pause.ogg", noise.hiss(0.2, RADIO.hiss_db)),
        ("key_on.ogg", noise.key_on()),
        ("key_off.ogg", noise.key_off()),
        ("radio_gap.ogg", silence(RADIO_GAP)),
    ];
    for (f, x) in computed {
        write_ogg(&x, &sounds.join(f), &tmp.0)?;
    }
    let clips: Vec<&Value> = v["clips"]
        .as_array()
        .context("voices.json: no \"clips\"")?
        .iter()
        .filter(|c| only.is_none_or(|o| c["file"].as_str().is_some_and(|f| f.contains(o))))
        .collect();
    let mut lines = vec![];
    for c in &clips {
        let (voice, speed) = role(&v, c["voice"].as_str().context("voices.json: a clip without \"voice\"")?)?;
        let text = c["say"].as_str().context("voices.json: a clip without \"say\"")?;
        lines.push(Line { text: text.into(), voice: voice.into(), speed });
    }
    check(cancel)?;
    let said = kokoro(repo, &lines, &tmp.0)?;
    for (i, (c, (x, split))) in clips.iter().zip(&said).enumerate() {
        check(cancel)?;
        let file = c["file"].as_str().context("voices.json: a clip without \"file\"")?;
        let y = make(x, *split, c, Mode::of(c["mode"].as_str().unwrap_or(""))?, &mut noise, &tmp.0)?;
        write_ogg(&y, &sounds.join(file), &tmp.0)?;
        pr.fraction((i + 1) as f32 / clips.len() as f32);
    }
    log!(pr, "voices: {} clips -> {}", clips.len(), sounds.display());
    let (rows, files) = crate::sim::own_sounds(data, assets, cancel)?;
    log!(pr, "voices: {rows} sound rows, {files} clips -> {}", assets.join(crate::sim::SOUNDS_DIR).display());
    Ok(())
}

/// `iaf-sim voices --say ROLE MODE TEXT OUT`: one line by a role of voices.json, made as `mode`, into `out` (the
/// approval samples).
pub fn say(data: &Path, repo: &Path, role_name: &str, mode: &str, text: &str, out: &Path) -> Result<()> {
    let v: Value = serde_json::from_str(&std::fs::read_to_string(data.join("sounds/voices.json"))?)?;
    let (voice, speed) = role(&v, role_name)?;
    let tmp = tmp_dir()?;
    let said = kokoro(repo, &[Line { text: text.into(), voice: voice.into(), speed }], &tmp.0)?;
    let (x, split) = &said[0];
    let c = json!({"say": text, "repeat": if mode == "betty" { 2 } else { 1 }});
    let y = make(x, *split, &c, Mode::of(mode)?, &mut Noise(SEED), &tmp.0)?;
    write_ogg(&y, out, &tmp.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(f: f32, s: f32) -> Vec<f32> {
        (0..(s * SR) as usize).map(|i| 0.5 * (std::f32::consts::TAU * f * i as f32 / SR).sin()).collect()
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|v| v * v).sum::<f32>() / x.len() as f32).sqrt()
    }

    /// The radio band passes 1 kHz and cuts 100 Hz and 6 kHz by over 20 dB.
    #[test]
    fn band_pass() {
        let gain = |f| {
            let mut x = tone(f, 0.5);
            band(&mut x, 300.0, 3000.0);
            20.0 * (rms(&x[2400..]) / rms(&tone(f, 0.5))).log10()
        };
        assert!(gain(1000.0).abs() < 1.0, "{}", gain(1000.0));
        assert!(gain(100.0) < -20.0 && gain(6000.0) < -20.0, "{} {}", gain(100.0), gain(6000.0));
    }

    /// The compressor brings a 20 dB step down to about 20 / ratio dB above the threshold.
    #[test]
    fn compressor() {
        let mut x: Vec<f32> = tone(1000.0, 0.5).iter().map(|v| v * 0.1).collect(); // -26 dB peak... then +20 dB
        x.extend(tone(1000.0, 0.5));
        compress(&mut x, -26.0, 4.0, 0.002, 0.06);
        let step = 20.0 * (rms(&x[18000..]) / rms(&x[6000..12000])).log10();
        assert!((step - 5.0).abs() < 1.5, "{step}");
    }

    /// Betty: the level, no clipping, the repeat after the gap; the radio clip carries both clicks.
    #[test]
    fn chains() {
        let word = [silence(0.2), tone(220.0, 0.4), silence(0.2)].concat();
        let b = betty(&word, &BETTY, 2);
        assert!((20.0 * vrms(&b).log10() - BETTY.vrms_db).abs() < 1.0, "{}", 20.0 * vrms(&b).log10());
        assert!(peak(&b) < 0.95, "{}", peak(&b));
        let one = betty(&word, &BETTY, 1).len();
        assert_eq!(b.len(), 2 * one + (SR * (BETTY.gap - 0.02)) as usize);
        let mut n = Noise(SEED);
        let r = radio(&word, Mode::Radio, &mut n);
        let p = radio(&word, Mode::Phrase, &mut Noise(SEED));
        assert_eq!(r.len(), p.len() + n.key_on().len() + n.key_off().len());
    }

    /// A keyed call: quiet, the click, the carrier's lead before the voice; after it the tail, the burst, the click
    /// and quiet again.
    #[test]
    fn key_timing() {
        let mut n = Noise(SEED);
        let (on, off, click) = (n.key_on(), n.key_off(), (0.002 * SR) as usize);
        let s = |t: f32| (t * SR) as usize;
        assert_eq!(on.len(), s(KEY.quiet_before) + click + s(KEY.lead));
        assert_eq!(off.len(), s(KEY.tail) + s(KEY.burst) + click + s(KEY.quiet_after));
        assert!(
            on[..s(KEY.quiet_before)].iter().all(|v| *v == 0.0)
                && off[off.len() - s(KEY.quiet_after)..].iter().all(|v| *v == 0.0)
        );
        let lead = &on[on.len() - s(KEY.lead)..];
        let db = 10.0 * (lead.iter().map(|v| v * v).sum::<f32>() / lead.len() as f32).log10();
        assert!((db - RADIO.hiss_db).abs() < 1.0, "{db}");
    }

    #[test]
    fn wav_round_trip() {
        let mut b = b"RIFF\0\0\0\0WAVEfmt \x10\0\0\0\x03\0\x01\0".to_vec();
        b.extend([0u8; 12]);
        b.extend(b"data\x08\0\0\0");
        b.extend(0.5f32.to_le_bytes());
        b.extend((-0.25f32).to_le_bytes());
        assert_eq!(read_wav(&b).unwrap(), vec![0.5, -0.25]);
    }
}
