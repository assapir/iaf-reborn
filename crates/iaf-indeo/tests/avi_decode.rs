use iaf_indeo::Decoder;
use std::path::PathBuf;

fn avi_path(name: &str) -> PathBuf {
    let install = std::env::var("IAF_INSTALL")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/install"));
    install.join("resource/avi").join(name)
}

fn fnv1a(data: &[u8]) -> u64 {
    data.iter().fold(0xcbf29ce484222325, |h, &b| (h ^ u64::from(b)).wrapping_mul(0x100000001b3))
}

/// Decodes every frame; returns the frame count and the RGB checksum of frame 100.
fn run(name: &str) -> Option<(usize, u64)> {
    let path = avi_path(name);
    let Ok(data) = std::fs::read(&path) else {
        eprintln!("skipped: no extracted game data (assets/install)");
        return None;
    };
    let avi = iaf_formats::avi::parse(&data).unwrap();
    assert_eq!(&avi.fourcc, b"IV50");
    assert_eq!((avi.width, avi.height), (320, 240));
    let dump = std::env::var("INDEO_DUMP").ok();
    let mut dec = Decoder::new();
    let (mut rgb, mut sum) = (Vec::new(), 0);
    for (i, r) in avi.video.iter().enumerate() {
        let f = dec.decode(&data[r.clone()]).unwrap_or_else(|e| panic!("{name} frame {i}: {e}"));
        assert_eq!((f.width, f.height), (320, 240));
        if let Some(dir) = &dump {
            let mut raw = f.y.clone();
            raw.extend(&f.u);
            raw.extend(&f.v);
            std::fs::write(format!("{dir}/{name}.{i}.yuv"), raw).unwrap();
        }
        if i == 100 {
            f.to_rgb(&mut rgb);
            assert_eq!(rgb.len(), 320 * 240 * 3);
            sum = fnv1a(&rgb);
        }
    }
    Some((avi.frame_count(), sum))
}

#[test]
fn janes_decodes() {
    if let Some((n, sum)) = run("janes.avi") {
        // 432 video chunks; the last 9 are 2-byte null frames (ffprobe counts the 423 decodable ones).
        assert_eq!(n, 432);
        assert_eq!(sum, 10223694388108467329, "janes frame 100 checksum");
    }
}

#[test]
fn intro_decodes() {
    if let Some((n, sum)) = run("intro.avi") {
        assert_eq!(n, 1402);
        assert_eq!(sum, 11373306220019369470, "intro frame 100 checksum");
    }
}
