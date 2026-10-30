# Our own store shapes for tools/stores/build.gd parts() (no open model exists for these; docs/aircraft-models.md
# §5.6): bodies of revolution with fins, in metres, nose at z 0 and aft +z, top +y. Lengths, diameters and spans from
# the published data (the sources in game/extra/models/stores/SOURCES.md); the rest (profiles, fin planforms, band
# positions, colours) measured by eye on the photos listed there (inferred). Colours sRGB (material colours).
extends RefCounted

## Paint (inferred from the photos).
const GREY := Color(0.60, 0.62, 0.63)
const DARK := Color(0.40, 0.41, 0.42)
const METAL := Color(0.72, 0.73, 0.74)
const OLIVE := Color(0.36, 0.38, 0.27)
const YELLOW := Color(0.85, 0.68, 0.12)
const RED := Color(0.62, 0.13, 0.10)
const BLACK := Color(0.08, 0.08, 0.09)
## The Popeye's gold-tinted seeker window (as the photo).
const GOLD := Color(0.52, 0.44, 0.20)

## Python 5: 3.1 m long, 160 mm across, 640 mm span; a glass dome nearly the body's width, two rows of four canards
## close behind it (small deltas, then larger clipped deltas), long-chord rear wings (X), each with a separate trailing
## control surface (the forked tips on the photos), two rail hangers on top: 16 surfaces (Wikipedia counts 18; open);
## grey, its guidance section darker, the motor bare metal with red bands (photos: Commons "Python-5").
const PY5_BODY := [
	[0.0, 0.0],
	[0.012, 0.045],
	[0.03, 0.062],
	[0.06, 0.074],
	[0.10, 0.078],
	[0.11, 0.080],
	[3.06, 0.080],
	[3.10, 0.066],
	[3.10, 0.0]
]
const PYTH5 := [
	{"lathe": PY5_BODY, "to": 0.10, "glass": true},
	{"lathe": PY5_BODY, "from": 0.10, "to": 0.95, "rgb": DARK},
	{"lathe": PY5_BODY, "from": 0.95, "to": 1.50, "rgb": GREY},
	{"lathe": PY5_BODY, "from": 1.50, "to": 1.53, "rgb": RED},
	{"lathe": PY5_BODY, "from": 1.53, "to": 2.94, "rgb": METAL},
	{"lathe": PY5_BODY, "from": 2.94, "to": 2.97, "rgb": RED},
	{"lathe": PY5_BODY, "from": 2.97, "rgb": DARK},
	{"fins": {"root": [0.16, 0.40], "tip": [0.36, 0.40], "r": 0.078, "h": 0.19, "roll": 45.0, "t": 0.006}, "rgb": GREY},
	{"fins": {"root": [0.42, 0.78], "tip": [0.68, 0.76], "r": 0.078, "h": 0.22, "roll": 45.0, "t": 0.007}, "rgb": GREY},
	{"fins": {"root": [2.46, 2.92], "tip": [2.80, 2.88], "r": 0.078, "h": 0.24, "roll": 45.0, "t": 0.008}, "rgb": GREY},
	{"fins": {"root": [2.93, 3.05], "tip": [2.96, 3.03], "r": 0.078, "h": 0.23, "roll": 45.0, "t": 0.006}, "rgb": GREY},
	{"box": [Vector3(0, 0.088, 1.05), Vector3(0.03, 0.02, 0.07)], "rgb": DARK},
	{"box": [Vector3(0, 0.088, 2.15), Vector3(0.03, 0.02, 0.07)], "rgb": DARK},
	{"box": [Vector3(0, 0.082, 1.60), Vector3(0.035, 0.012, 1.6)], "rgb": GREY},
]

## GBU-39/B SDB: 1.80 m long, 190 mm across; a long ogive nose, the folded wing pack along the top, four small tail fins
## (X); grey with a yellow band behind the nose (photos: Commons "GBU-39 Small Diameter Bomb", the Boeing rendering).
const SDB_BODY := [
	[0.0, 0.0],
	[0.015, 0.016],
	[0.07, 0.042],
	[0.17, 0.068],
	[0.30, 0.086],
	[0.45, 0.095],
	[1.56, 0.095],
	[1.70, 0.082],
	[1.80, 0.062],
	[1.80, 0.0]
]
const GBU39 := [
	{"lathe": SDB_BODY, "to": 0.38, "rgb": GREY},
	{"lathe": SDB_BODY, "from": 0.38, "to": 0.43, "rgb": YELLOW},
	{"lathe": SDB_BODY, "from": 0.43, "rgb": GREY},
	{"box": [Vector3(0, 0.103, 0.95), Vector3(0.11, 0.03, 1.02)], "taper": 0.85, "rgb": DARK},
	{"box": [Vector3(0, 0.122, 0.95), Vector3(0.15, 0.010, 1.04)], "rgb": GREY},
	{
		"fins": {"root": [1.52, 1.79], "tip": [1.68, 1.79], "r": 0.085, "h": 0.085, "roll": 45.0, "t": 0.006},
		"rgb": GREY
	},
]

## BRU-61/A: 3.63 × 0.41 × 0.41 m (143 × 16 × 16 in); a squared beam with rounded ends, an ejector keel below; grey.
## Stretched along its length at run time to the station's four slots (util/gltf.gd RACKS).
const BRU_BODY := [[0.0, 0.0], [0.04, 0.09], [0.18, 0.15], [0.35, 0.16], [3.30, 0.16], [3.55, 0.11], [3.63, 0.0]]
const BRU61 := [
	{"lathe": BRU_BODY, "sq": 5.0, "rgb": DARK, "n": 40},
	{"box": [Vector3(0, -0.17, 1.815), Vector3(0.36, 0.07, 3.1)], "taper": 1.15, "rgb": DARK},
]

## Popeye (AGM-142): 4.82 m long, 533 mm across, 1.98 m span; a gold-tinted dome, small swept fins (X) behind the
## nose, long-chord swept tail fins (X); grey with a yellow band (photo: Commons "Popey missile").
const POP_BODY := [
	[0.0, 0.0],
	[0.03, 0.11],
	[0.09, 0.16],
	[0.18, 0.19],
	[0.22, 0.205],
	[0.60, 0.235],
	[1.20, 0.262],
	[1.60, 0.2665],
	[4.62, 0.2665],
	[4.82, 0.22],
	[4.82, 0.0]
]
const POPEYE := [
	{"lathe": POP_BODY, "to": 0.18, "rgb": GOLD},
	{"lathe": POP_BODY, "from": 0.18, "to": 1.75, "rgb": GREY},
	{"lathe": POP_BODY, "from": 1.75, "to": 1.82, "rgb": YELLOW},
	{"lathe": POP_BODY, "from": 1.82, "rgb": GREY},
	{"fins": {"root": [1.00, 1.45], "tip": [1.30, 1.45], "r": 0.25, "h": 0.13, "roll": 45.0, "t": 0.012}, "rgb": GREY},
	{"fins": {"root": [3.70, 4.76], "tip": [4.40, 4.80], "r": 0.26, "h": 0.73, "roll": 45.0, "t": 0.02}, "rgb": GREY},
	{"box": [Vector3(0, 0.28, 1.9), Vector3(0.08, 0.04, 0.12)], "rgb": DARK},
	{"box": [Vector3(0, 0.28, 2.66), Vector3(0.08, 0.04, 0.12)], "rgb": DARK},
]

## SPICE 1000: a kit on the Mk 83 (356 mm across); a long tapered guidance nose with four small canards (X), the Mk 83
## body, a tail cone with four fins (X) and the folded wing pack under the body. About 3.8 m long (inferred from the
## photo: no published length); the body olive with a yellow band, the kit grey (photo: Commons "ILA Berlin 2012 PD
## 035", an inert blue body there).
const SP1_BODY := [
	[0.0, 0.0],
	[0.02, 0.055],
	[0.08, 0.085],
	[0.40, 0.112],
	[0.90, 0.145],
	[1.40, 0.170],
	[1.60, 0.178],
	[2.90, 0.178],
	[3.25, 0.150],
	[3.62, 0.100],
	[3.80, 0.070],
	[3.80, 0.0]
]
const SPICE1000 := [
	{"lathe": SP1_BODY, "to": 0.04, "glass": true},
	{"lathe": SP1_BODY, "from": 0.04, "to": 1.62, "rgb": GREY},
	{"lathe": SP1_BODY, "from": 1.62, "to": 1.70, "rgb": YELLOW},
	{"lathe": SP1_BODY, "from": 1.70, "to": 2.92, "rgb": OLIVE},
	{"lathe": SP1_BODY, "from": 2.92, "rgb": GREY},
	{"fins": {"root": [0.85, 1.15], "tip": [1.07, 1.15], "r": 0.14, "h": 0.10, "roll": 45.0, "t": 0.01}, "rgb": GREY},
	{"fins": {"root": [3.15, 3.72], "tip": [3.55, 3.76], "r": 0.12, "h": 0.25, "roll": 45.0, "t": 0.012}, "rgb": GREY},
	{"box": [Vector3(0, -0.195, 2.35), Vector3(0.22, 0.05, 2.1)], "taper": 1.2, "rgb": GREY},
	{"box": [Vector3(0, -0.225, 2.40), Vector3(0.40, 0.015, 1.9)], "rgb": GREY},
	{"box": [Vector3(0, 0.19, 1.95), Vector3(0.05, 0.03, 0.10)], "rgb": DARK},
	{"box": [Vector3(0, 0.19, 2.71), Vector3(0.05, 0.03, 0.10)], "rgb": DARK},
]

## SPICE 2000: a kit on the Mk 84 (457 mm across); a guidance nose with four canards (X), four long mid-body strakes
## (X), a tail cone with four fins (X): the 12 control surfaces in three groups. About 4.4 m long (inferred: none
## published); the body olive with a yellow band, the kit grey (photo: Commons "Spice bomb front").
const SP2_BODY := [
	[0.0, 0.0],
	[0.025, 0.07],
	[0.10, 0.11],
	[0.50, 0.145],
	[1.10, 0.19],
	[1.65, 0.222],
	[1.85, 0.2285],
	[3.40, 0.2285],
	[3.80, 0.19],
	[4.25, 0.13],
	[4.40, 0.09],
	[4.40, 0.0]
]
const SPICE2000 := [
	{"lathe": SP2_BODY, "to": 0.05, "glass": true},
	{"lathe": SP2_BODY, "from": 0.05, "to": 1.87, "rgb": GREY},
	{"lathe": SP2_BODY, "from": 1.87, "to": 1.96, "rgb": YELLOW},
	{"lathe": SP2_BODY, "from": 1.96, "to": 3.42, "rgb": OLIVE},
	{"lathe": SP2_BODY, "from": 3.42, "rgb": GREY},
	{"fins": {"root": [0.95, 1.30], "tip": [1.20, 1.30], "r": 0.18, "h": 0.17, "roll": 45.0, "t": 0.012}, "rgb": GREY},
	{"fins": {"root": [2.00, 3.30], "tip": [2.25, 3.25], "r": 0.225, "h": 0.13, "roll": 45.0, "t": 0.012}, "rgb": GREY},
	{"fins": {"root": [3.70, 4.32], "tip": [4.12, 4.36], "r": 0.16, "h": 0.32, "roll": 45.0, "t": 0.014}, "rgb": GREY},
	{"box": [Vector3(0, 0.245, 2.30), Vector3(0.06, 0.035, 0.12)], "rgb": DARK},
	{"box": [Vector3(0, 0.245, 3.06), Vector3(0.06, 0.035, 0.12)], "rgb": DARK},
]

## Spike NLOS (Tamuz): about 1.7 m long; a dark hemispherical seeker dome, a cylindrical body, four long narrow pop-out
## wings (X, open) behind the middle, four small tail fins (X), a raceway on top; light grey. Diameter about 170 mm
## (inferred from the photo against the length; open) (photo: Commons "Spike NLOS Missile FSMU (ADAS 2016)").
const NLOS_BODY := [
	[0.0, 0.0], [0.015, 0.05], [0.04, 0.072], [0.075, 0.085], [0.09, 0.085], [1.66, 0.085], [1.70, 0.07], [1.70, 0.0]
]
const SPIKE_NLOS := [
	{"lathe": NLOS_BODY, "to": 0.06, "glass": true},
	{"lathe": NLOS_BODY, "from": 0.06, "to": 0.10, "rgb": BLACK},
	{"lathe": NLOS_BODY, "from": 0.10, "rgb": GREY},
	{"fins": {"root": [0.92, 1.04], "tip": [0.94, 1.04], "r": 0.085, "h": 0.62, "roll": 45.0, "t": 0.008}, "rgb": GREY},
	{"fins": {"root": [1.50, 1.69], "tip": [1.60, 1.69], "r": 0.085, "h": 0.09, "roll": 45.0, "t": 0.006}, "rgb": GREY},
	{"box": [Vector3(0, 0.092, 0.85), Vector3(0.03, 0.016, 1.1)], "rgb": GREY},
]
