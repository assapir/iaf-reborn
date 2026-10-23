//! USB HID report descriptors (HID 1.11 §6.2.2): how many axes a joystick reports. Godot / SDL give the axes by
//! number only, so the game reads the device's own descriptor to tell a 5th axis (docs/controls.md §5.2).

/// The input axes a report descriptor declares: the variable, non-constant Input fields whose usage is a Generic
/// Desktop axis (X, Y, Z, Rx, Ry, Rz, Slider, Dial, Wheel) or a Simulation control (rudder, throttle,
/// accelerator, brake). Short items only; long items are skipped.
pub fn input_axes(desc: &[u8]) -> usize {
    let mut page = 0u32;
    let mut count = 0u32;
    let mut usages: Vec<u32> = Vec::new();
    let mut range: Option<(u32, u32)> = None;
    let mut axes = 0;
    let mut i = 0;
    while i < desc.len() {
        let prefix = desc[i];
        if prefix == 0xfe {
            // Long item: size, tag, data.
            i += 3 + *desc.get(i + 1).unwrap_or(&0) as usize;
            continue;
        }
        let size = [0, 1, 2, 4][(prefix & 3) as usize];
        let data = desc.get(i + 1..i + 1 + size).unwrap_or(&[]);
        let value = data.iter().rev().fold(0u32, |v, &b| v << 8 | b as u32);
        i += 1 + size;
        // A usage with 4 data bytes carries its own page in the high half.
        let full = |v: u32| if size == 4 { v } else { page << 16 | v };
        match prefix & 0xfc {
            0x04 => page = value,
            0x94 => count = value,
            0x08 => usages.push(full(value)),
            0x18 => range = Some((full(value), range.map_or(0, |r| r.1))),
            0x28 => range = Some((range.map_or(0, |r| r.0), full(value))),
            0x80 | 0x90 | 0xb0 | 0xa0 | 0xc0 => {
                // Input: data (bit 0 clear) and variable (bit 1 set) fields take the usages in order, the last
                // one repeating.
                if prefix & 0xfc == 0x80 && value & 3 == 2 {
                    let mut list = usages.clone();
                    if let Some((lo, hi)) = range {
                        list.extend(lo..=hi);
                    }
                    axes += (0..count as usize)
                        .filter_map(|k| list.get(k).or(list.last()))
                        .filter(|&&u| is_axis(u))
                        .count();
                }
                usages.clear();
                range = None;
            }
            _ => {}
        }
    }
    axes
}

fn is_axis(usage: u32) -> bool {
    matches!(usage >> 16, 0x01 if (0x30..=0x38).contains(&(usage & 0xffff)))
        || matches!(usage >> 16, 0x02 if matches!(usage & 0xffff, 0xba | 0xbb | 0xc4 | 0xc5))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
    }

    #[test]
    fn hotas_x_has_five_axes() {
        // The T.Flight Hotas X (044f:b108) as macOS lists it: 12 buttons, a hat, X / Y (10 bit), Z / Rz / Slider
        // (8 bit), an output rudder report and vendor bytes.
        let d = hex(concat!(
            "05010904a10105091901290c15002501350045017501950c810295017504810105010939150025073500463b0165147504950181",
            "42810105010930150026ff03350046ff036500750a95018102750681010931750a810275068101093209350936150026ff003500",
            "46ff00650075089503810206010009bb7508950291020600ff0920092109220923092409250926092709280929092a092b950c81",
            "020a212675089508b10227ffff00000902090175109502b1a2c0"
        ));
        assert_eq!(input_axes(&d), 5);
    }

    #[test]
    fn gamepad_ranges_and_constants() {
        // Usage Minimum X .. Maximum Rz over 6 fields, then 2 constant padding fields: 6 axes.
        let d = hex("05010905a1011930293515002507750895068102750895028101c0");
        assert_eq!(input_axes(&d), 6);
    }
}
