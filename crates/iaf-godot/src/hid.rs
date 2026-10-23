//! `IafHid`: how many axes the joystick reports (`iaf_formats::hid::input_axes` on its USB HID report descriptor),
//! for `controls/joystick.gd`. macOS lists the descriptors in the I/O Registry (`ioreg`), Linux in sysfs; neither
//! opens the device. Elsewhere the count is unknown.

use godot::prelude::*;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafHid {}

#[godot_api]
impl IafHid {
    /// The input axes of the device with this SDL GUID (`Input.get_joy_guid`), −1 when unknown.
    #[func]
    fn axis_count(guid: GString) -> i64 {
        ids(&guid.to_string())
            .and_then(|(v, p)| descriptors(v, p).iter().map(|d| iaf_formats::hid::input_axes(d)).max())
            .map_or(-1, |n| n as i64)
    }
}

/// The USB vendor and product ids in an SDL GUID: bytes 4–5 and 8–9, little-endian.
fn ids(guid: &str) -> Option<(u16, u16)> {
    let b = |i: usize| u8::from_str_radix(guid.get(i * 2..i * 2 + 2)?, 16).ok();
    let (v, p) = (u16::from_le_bytes([b(4)?, b(5)?]), u16::from_le_bytes([b(8)?, b(9)?]));
    (v != 0).then_some((v, p))
}

#[cfg(target_os = "macos")]
fn descriptors(vendor: u16, product: u16) -> Vec<Vec<u8>> {
    let out = std::process::Command::new("ioreg").args(["-r", "-c", "IOHIDDevice", "-d", "1", "-l", "-w0"]).output();
    out.map_or(Vec::new(), |o| ioreg_descriptors(&String::from_utf8_lossy(&o.stdout), vendor, product))
}

#[cfg(target_os = "linux")]
fn descriptors(vendor: u16, product: u16) -> Vec<Vec<u8>> {
    // uevent: HID_ID=<bus>:<vendor>:<product> in hex, e.g. HID_ID=0003:0000044F:0000B108.
    let want = format!(":{vendor:08X}:{product:08X}");
    let Ok(dir) = std::fs::read_dir("/sys/class/hidraw") else { return Vec::new() };
    dir.flatten()
        .map(|e| e.path().join("device"))
        .filter(|d| std::fs::read_to_string(d.join("uevent")).is_ok_and(|u| u.to_uppercase().contains(&want)))
        .filter_map(|d| std::fs::read(d.join("report_descriptor")).ok())
        .collect()
}

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
fn descriptors(_vendor: u16, _product: u16) -> Vec<Vec<u8>> {
    Vec::new()
}

/// The report descriptors of the `ioreg -l` entries ("+-o" blocks) with these ids.
#[cfg(any(target_os = "macos", test))]
fn ioreg_descriptors(text: &str, vendor: u16, product: u16) -> Vec<Vec<u8>> {
    let prop = |block: &str, key: &str| {
        let line = block.lines().find(|l| l.trim_start().starts_with(&format!("\"{key}\" = ")))?;
        Some(line.split_once(" = ")?.1.trim().to_string())
    };
    text.split("+-o ")
        .filter(|b| {
            prop(b, "VendorID") == Some(vendor.to_string()) && prop(b, "ProductID") == Some(product.to_string())
        })
        .filter_map(|b| {
            let hex = prop(b, "ReportDescriptor")?;
            let hex = hex.trim_start_matches('<').trim_end_matches('>');
            (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(hex.get(i..i + 2)?, 16).ok()).collect()
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn guid_ids() {
        assert_eq!(ids("0300ae364f04000008b1000000010000"), Some((0x044f, 0xb108)));
        assert_eq!(ids("0000000000000000000000000000000"), None);
    }

    #[test]
    fn ioreg_blocks() {
        let text = "+-o Other  <class X>\n    {\n      \"ReportDescriptor\" = <0501>\n      \"VendorID\" = 1452\n\
                    +-o AppleUserUSBHostHIDDevice  <class AppleUserHIDDevice>\n    {\n      \"VendorID\" = 1103\n\
                    \"ProductID\" = 45320\n      \"ReportDescriptor\" = <05010904c0>\n    }\n";
        assert_eq!(ioreg_descriptors(text, 0x044f, 0xb108), vec![vec![0x05, 0x01, 0x09, 0x04, 0xc0]]);
    }
}
