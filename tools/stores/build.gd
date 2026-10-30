# Builds the detailed store models (Graphics → MORE → Models: Detailed; docs/aircraft-models.md §5) from FlightGear
# aircraft's stores (AC3D files and their textures: the F-16, the MiG-21bis, the MiG-29 9-12) and fits each onto the
# original model of the store it replaces: its length, its body's axis and its nose direction, so the game's rack
# slots, release points and trails stay.
# Writes game/extra/models/stores/<name>.glb (JPEG textures; the CBU-97 shows the CBU-87's, util/gltf.gd STORES).
# Needs the FlightGear checkouts in one folder (f16 at ef4f192, MiG-21bis at 9ca6f5b, MiG-29_9-12 at d4a299b;
# docs/aircraft-models.md §5.3) and the converted install (tools/setup-cli.sh):
#
#   IAF_DEFAULT_SETTINGS=1 godot --headless --path game -s ../tools/stores/build.gd -- /tmp/fg "$PWD/assets" [name …]
#
# STORES_STATS=1 only prints each model's measurements (no files written).
extends SceneTree

## Per store: `orig` (the original under converted/objects/weapons), `ac` (FlightGear files under `dir`, default the
## F-16's Models/Armament; `dir` relative to the checkouts' folder),
## `drop` (AC object names left out, as prefixes), `livery` (a texture under Models/ in place of the AC's, cropped to
## the faces' UVs), `kit` (the GBU-12's Paveway II guidance and tail kits on the bomb, KIT_*), `scale_as` (another
## store's scale instead of the original's length: the laser bombs keep their bomb's girth and are longer than the
## original, which has the plain bomb's length), `top` (its top on the original's top, where the pylon meets it,
## instead of its axis on the original's: the tanks and pods whose FlightGear mounts stand above the body), `dy`
## (metres up after the fit), `tris` (decimated to about that), `tint` (the texture's colour factor: the MiG-29 9-12's
## textures are plain white, with no baked shading).
## Every model is scaled uniformly to the original's length, its centre on the original's, its axis (FlightGear's
## origin line) on the original's (the mean of its nose and tail centroids).
## Our own stores' shapes (parts()).
const Ours := preload("res://../tools/stores/ours.gd")
const F16 := "f16/Models/Armament"
const GBU31_AC := "Weapons/GBU-31/GBU-31.ac"
const MIG21 := "MiG-21bis/Models/Stores"
const MIG29 := "MiG-29_9-12/Models/Submodels"
## The Soviet missiles' light grey paint over their white textures (ours, set by eye; sRGB, a material colour).
const PAINT_29 := Color(0.74, 0.75, 0.76)
const PAINT_21 := Color(0.86, 0.86, 0.87)
const STORES := {
	"aim9": {"orig": "aim9/aim9_m.gltf", "ac": ["Weapons/AIM-9M/AIM-9M.ac"]},
	"aim7": {"orig": "aim7/aim7_m.gltf", "ac": ["Weapons/AIM-7/AIM-7F.ac"]},
	"aim120": {"orig": "aim120/aim120_m.gltf", "ac": ["Weapons/AIM-120/AIM-120B.ac"]},
	"agm65": {"orig": "agm65/agm65_m.gltf", "ac": ["Weapons/AGM-65D/AGM-65D.ac"]},
	"agm88": {"orig": "agm88/agm88_m.gltf", "ac": ["Weapons/AGM-88/AGM-88.ac"]},
	"mk82": {"orig": "mk82/mk82_m.gltf", "ac": ["Weapons/MK-82/MK-82.ac"]},
	"mk83": {"orig": "mk83/mk83_m.gltf", "ac": ["Weapons/MK-83/MK-83.ac"]},
	"mk84": {"orig": "mk84/mk84_m.gltf", "ac": ["Weapons/MK-84/MK-84.ac"]},
	"mk82lb":
	{"orig": "mk82lb/mk82lb_m.gltf", "ac": ["Weapons/GBU-12/GBU-12.ac"], "scale_as": "mk82", "glass": ["GBU-12_Glass"]},
	"mk83lb":
	{
		"orig": "mk83lb/mk83lb_m.gltf",
		"ac": ["Weapons/MK-83/MK-83.ac"],
		"drop": ["MK-83_Detonator", "MK-83_TailFins", "MK-83_Wiring"],
		"kit": true,
		"scale_as": "mk83"
	},
	"mk84lb":
	{
		"orig": "mk84lb/mk84lb_m.gltf",
		"ac": ["Weapons/MK-84/MK-84.ac"],
		"drop": ["MK-84_Detonator", "MK-84_TailFins", "MK-84_Wiring"],
		"kit": true,
		"scale_as": "mk84"
	},
	# The modern weapons (modern_weapons.gd): on the original store each stands in for, at the real size of the
	# bomb it is built on (scale_as), so the JDAMs are longer than the plain bombs.
	"aim9x": {"orig": "aim9/aim9_m.gltf", "ac": ["Weapons/AIM-9X/AIM-9X.ac"], "scale_as": "aim9"},
	"gbu31": {"orig": "mk84/mk84_m.gltf", "ac": ["Weapons/GBU-31/GBU-31.ac"], "scale_as": "mk84"},
	"gbu38": {"orig": "mk82/mk82_m.gltf", "ac": ["Weapons/GBU-54/GBU-54.ac"], "scale_as": "mk82"},
	# The GBU-32 (1000 lb JDAM): the GBU-31 scaled to its real length, 3.035 m of 3.880 (k; the Mk 83 / Mk 84 bodies
	# have nearly the same length over diameter); on the MK-83L it stands in for, at the Mk-83's scale.
	"gbu32": {"orig": "mk83lb/mk83lb_m.gltf", "ac": ["Weapons/GBU-31/GBU-31.ac"], "scale_as": "mk83", "k": 0.7822},
	# The GBU-31(V)3 / (V)4 (the BLU-109's JDAM): the GBU-31 at its real length, 3.774 m, slimmer by `girth` to the
	# BLU-109's 370 mm over the Mk 84's 460 mm (tail kit too; inferred).
	"gbu31v3": {"orig": "mk84/mk84_m.gltf", "ac": [GBU31_AC], "scale_as": "mk84", "k": 0.9727, "girth": 0.804},
	# Ours (no open model; parts(), shapes and sources in SOURCES.md): the Python 5 on the Python 4 at the AIM-9's
	# scale; the GBU-39 on the MK-82 (the record's 0.8 scale shrinks it once released) and its BRU-61/A rack, which
	# util/gltf.gd RACKS draws over a station of four; the Popeye on its original; the SPICE 1000 / 2000 and the
	# Spike NLOS at their real size (no game record yet: docs/real-weapons.md §1.8).
	"pyth5": {"orig": "pthon4/pthon4_m.gltf", "parts": Ours.PYTH5, "scale_as": "aim9"},
	"gbu39": {"orig": "mk82/mk82_m.gltf", "parts": Ours.GBU39, "scale_as": "mk82"},
	"bru61": {"parts": Ours.BRU61},
	"popeye": {"orig": "popeye/popeye_m.gltf", "parts": Ours.POPEYE},
	"spice1000": {"parts": Ours.SPICE1000},
	"spice2000": {"parts": Ours.SPICE2000},
	"spikenlos": {"parts": Ours.SPIKE_NLOS},
	"cbu87": {"orig": "cbu87/cbu87_m.gltf", "ac": ["Weapons/CBU-87/CBU-87.ac"], "drop": ["BLU-97"], "tris": 5000},
	"f16ftk":
	{
		"orig": "f16ftk/f16ftk_m.gltf",
		"ac": ["External-stores/Fueltanks/370G.ac"],
		"livery": "Liveries/Block40/90-0874.png"
	},
	"f16ftkm":
	{
		"orig": "f16ftk/f16ftkm.gltf",
		"ac": ["External-stores/Fueltanks/300G.ac"],
		"drop": ["pylon"],
		"livery": "Liveries/Block40/90-0874.png",
		"top": true
	},
	"ecmpod": {"orig": "ecmpod/ecmpod_m.gltf", "ac": ["External-stores/AN_ALQ-131/AN_ALQ-131.ac"], "top": true},
	"flrpod": {"orig": "flrpod/flrpod_m.gltf", "ac": ["External-stores/LANTIRN/AN-AAQ-13.ac"], "top": true},
	# The Soviet stores (phase 2): the MiG-21bis's (OPRF, GPL-3.0) and the MiG-29 9-12's (S. Salov, GPL-3.0).
	"aa2": {"orig": "aa2/aa2_m.gltf", "dir": MIG21, "ac": ["R-3S/r-3s.ac"], "glass": ["glass"], "tint": PAINT_21},
	"aa8": {"orig": "aa8/aa8_m.gltf", "dir": MIG29, "ac": ["R-60M/R-60M.ac"], "tint": PAINT_29},
	"aa10": {"orig": "aa10/aa10_m.gltf", "dir": MIG29, "ac": ["R-27R/R-27R.ac"], "tint": PAINT_29},
	"aa11": {"orig": "aa11/aa11_m.gltf", "dir": MIG29, "ac": ["R-73/R-73.ac"], "tint": PAINT_29},
	"mig29ftk":
	{"orig": "../controllableplanes/mig29/mig29ftk_m.gltf", "dir": MIG29, "ac": ["PTB-1500/PTB-1500.ac"], "top": true},
}

## The GBU-12's Paveway II kits for the kitbashed Mk-83L / Mk-84L (GBU-16 / GBU-10 look, inferred). The guidance
## section (the body's faces ahead of KIT_SEAM, z in the GBU-12's frame, and the canards and seeker glass) goes at its
## full size on the bomb's nose (Paveway II bombs share it). The tail kit (KIT_TAIL objects, from KIT_TAIL_Z where
## the GBU-12's body has radius KIT_TAIL_R) is scaled by the bomb's girth over the Mk-82's (KIT_BODY_R) and starts
## where the bomb's body has that radius.
const KIT_AC := "Weapons/GBU-12/GBU-12.ac"
const KIT_BODY := "GBU-12"
const KIT_FRONT := ["GBU-12_FrontWing", "GBU-12_Glass"]
const KIT_TAIL := ["GBU-12_Tail", "GBU-12_Wing"]
const KIT_SEAM := -0.42
const KIT_TAIL_Z := 0.84
const KIT_TAIL_R := 0.132
const KIT_BODY_R := 0.139
## Seeker glass and lenses (untextured, see-through in FlightGear): opaque dark glass here (one shader for every store).
const GLASS := Color(0.06, 0.07, 0.08)

var src := ""
var fg := ""
var assets := ""
var out_dir := ""
var stats := false


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		printerr("usage: -- <folder of the FlightGear checkouts> <assets dir> [store …]")
		quit(2)
		return
	src = a[0]
	fg = src.path_join("f16/Models")
	assets = a[1]
	out_dir = ProjectSettings.globalize_path("res://extra/models/stores")
	stats = OS.get_environment("STORES_STATS") == "1"
	var names: Array = a.slice(2) if a.size() > 2 else STORES.keys()
	DirAccess.make_dir_recursive_absolute(out_dir)
	for n in names:
		build(n, STORES[n])
	quit()


# --- AC3D ------------------------------------------------------------------------------------------------------


## An AC3D file's objects in Godot's frame (AC x aft, y up, z left -> Godot x right, y up, z aft; nose −Z):
## [{name, tex (path or ""), verts: PackedVector3Array, faces: [{idx, uv, mat, smooth, two}], crease}], materials
## [{rgb: Color, trans}].
func read_ac(path: String) -> Dictionary:
	var lines := FileAccess.get_file_as_string(path).replace("\r", "").split("\n")  # some are CRLF
	var mats := []
	var objs := []
	var i := 0
	while i < lines.size() and not lines[i].begins_with("OBJECT"):
		if lines[i].begins_with("MATERIAL"):
			var t := lines[i].split(" ", false)
			var k := t.find("rgb")
			var tr := t.find("trans")
			mats.append(
				{
					"rgb": Color(float(t[k + 1]), float(t[k + 2]), float(t[k + 3])),
					"trans": float(t[tr + 1]) if tr >= 0 else 0.0
				}
			)
		i += 1
	var st := [i]
	_read_object(lines, st, Transform3D.IDENTITY, objs, path.get_base_dir())
	return {"objects": objs, "mats": mats}


func _read_object(lines: PackedStringArray, st: Array, parent: Transform3D, out: Array, dir: String) -> void:
	st[0] += 1
	var o := {"name": "", "tex": "", "crease": 30.0, "faces": []}
	var loc := Vector3.ZERO
	var rot := Basis.IDENTITY
	var verts := PackedVector3Array()
	while st[0] < lines.size():
		var line := lines[st[0]]
		var t := line.split(" ", false)
		st[0] += 1
		if t.is_empty():
			continue
		match t[0]:
			"name":
				o.name = line.split('"')[1]
			"data":
				st[0] += 1
			"texture":
				o.tex = dir.path_join(line.split('"')[1].replace("\\", "/")).simplify_path()
			"loc":
				loc = Vector3(float(t[1]), float(t[2]), float(t[3]))
			"rot":
				var r := Array(t.slice(1)).map(func(x): return float(x))
				rot = Basis(Vector3(r[0], r[1], r[2]), Vector3(r[3], r[4], r[5]), Vector3(r[6], r[7], r[8]))
			"crease":
				o.crease = float(t[1])
			"numvert":
				for j in int(t[1]):
					var v := lines[st[0] + j].split(" ", false)
					verts.append(Vector3(float(v[0]), float(v[1]), float(v[2])))
				st[0] += int(t[1])
			"numsurf":
				for _s in int(t[1]):
					var flags := lines[st[0]].split(" ", false)[1].hex_to_int()
					st[0] += 1
					var mi := 0
					while not lines[st[0]].begins_with("refs"):
						if lines[st[0]].begins_with("mat"):
							mi = int(lines[st[0]].split(" ", false)[1])
						st[0] += 1
					var n := int(lines[st[0]].split(" ", false)[1])
					var idx := PackedInt32Array()
					var uv := PackedVector2Array()
					for j in n:
						var r := lines[st[0] + 1 + j].split(" ", false)
						idx.append(int(r[0]))
						uv.append(Vector2(float(r[1]), 1.0 - float(r[2])))
					st[0] += 1 + n
					if flags & 0xF == 0 and n >= 3:
						o.faces.append({"idx": idx, "uv": uv, "mat": mi, "smooth": bool(flags & 0x10)})
			"kids":
				var mw := parent * Transform3D(rot, loc)
				var to_g := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))  # columns: AC x, y, z
				var w := PackedVector3Array()
				for v in verts:
					w.append(to_g * (mw * v))
				o["verts"] = w
				if not o.faces.is_empty():
					out.append(o)
				for _k in int(t[1]):
					_read_object(lines, st, mw, out, dir)
				return


# --- the original ----------------------------------------------------------------------------------------------


## The original model's vertices (its frame; the `pilon` helper left out).
func original_verts(rel: String) -> PackedVector3Array:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_DISCARD_TEXTURES
	var out := PackedVector3Array()
	if doc.append_from_file(assets.path_join("converted/objects/weapons").path_join(rel), state) != OK:
		push_error("no original " + rel)
		return out
	var root := doc.generate_scene(state) as Node3D
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).to_lower() == "pilon":
			continue
		var x := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			x = (n as Node3D).transform * x
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				out.append(x * v)
	root.free()
	return out


# --- measuring and fitting -------------------------------------------------------------------------------------


## A store's long-axis measurements: {z0, z1 (its ends), axis (x, y of its centre line: the mean of its nose's and its
## tail's centroids, the vertices within END of each end), lo, hi (its bounds)}.
static func measure(verts: PackedVector3Array) -> Dictionary:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var ends := [Vector3.ZERO, Vector3.ZERO]
	var len := hi.z - lo.z
	for v in verts:
		if v.z < lo.z + END * len:
			ends[0] += Vector3(v.x, v.y, 1)
		elif v.z > hi.z - END * len:
			ends[1] += Vector3(v.x, v.y, 1)
	var nose: Vector2 = Vector2(ends[0].x, ends[0].y) / ends[0].z
	var tail: Vector2 = Vector2(ends[1].x, ends[1].y) / ends[1].z
	return {"z0": lo.z, "z1": hi.z, "axis": (nose + tail) * 0.5, "nose": nose, "tail": tail, "lo": lo, "hi": hi}


const END := 0.03

# --- building --------------------------------------------------------------------------------------------------


func build(name: String, spec: Dictionary) -> void:
	var objs := load_objects(spec)
	if spec.get("kit", false):
		objs.append_array(kit(objs))
	var verts := PackedVector3Array()
	for o in objs:
		verts.append_array(o.verts)
	var m := measure(verts)
	var om := measure(original_verts(spec.orig)) if spec.has("orig") else _centred(m)
	var tris := 0
	for o in objs:
		for fc in o.faces:
			tris += fc.idx.size() - 2
	print("%s (%d tris)" % [name, tris])
	for x in [["FG", m], ["orig", om]]:
		var d: Dictionary = x[1]
		print(
			(
				"  %-4s len %.3f  w %.3f h %.3f  y %.3f..%.3f  nose %s tail %s"
				% [x[0], d.z1 - d.z0, d.hi.x - d.lo.x, d.hi.y - d.lo.y, d.lo.y, d.hi.y, d.nose, d.tail]
			)
		)
	if stats:
		for o in objs:
			var b := measure(o.verts)
			print("   %s: z %.3f..%.3f faces %d tex %s" % [o.name, b.z0, b.z1, o.faces.size(), o.tex.get_file()])
			if OS.get_environment("STORES_PROFILE") in o.name:
				var bins := {}
				for v in o.verts:
					var k := int(floor(v.z * 20.0))
					bins[k] = maxf(bins.get(k, 0.0), Vector2(v.x, v.y).length())
				var ks := bins.keys()
				ks.sort()
				print("     ", " ".join(ks.map(func(k): return "%.2f:%.3f" % [k / 20.0, bins[k]])))
		return
	var s: float = (om.z1 - om.z0) / (m.z1 - m.z0)
	if spec.has("scale_as"):
		var other: Dictionary = STORES[spec.scale_as]
		var a := measure(_all_verts(load_objects(other)))
		var b := measure(original_verts(other.orig))
		s = (b.z1 - b.z0) / (a.z1 - a.z0)
	s *= float(spec.get("k", 1.0))
	var g := float(spec.get("girth", 1.0))
	var fit := Transform3D(
		Basis.from_scale(Vector3(s * g, s * g, s)),
		Vector3(om.axis.x, om.axis.y + float(spec.get("dy", 0.0)), (om.z0 + om.z1 - s * (m.z0 + m.z1)) * 0.5)
	)
	if spec.get("top", false):
		fit.origin.y = om.hi.y - s * m.hi.y + float(spec.get("dy", 0.0))
	print("  fit: scale %.3f, %s" % [s, fit.origin])
	var root := Node3D.new()
	root.name = name
	var mi := MeshInstance3D.new()
	mi.name = name + "_body"
	mi.mesh = make_mesh(objs, fit, spec, int(spec.get("tris", 0)))
	root.add_child(mi)
	mi.owner = root
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.85
	var state := GLTFState.new()
	if (
		doc.append_from_scene(root, state) != OK
		or doc.write_to_filesystem(state, out_dir.path_join(name + ".glb")) != OK
	):
		push_error("export failed: " + name)
	root.free()


## A store with no original (ours, not a game weapon yet): its own measurements moved onto the origin, so the fit
## keeps its size and centres it.
static func _centred(m: Dictionary) -> Dictionary:
	var c := m.duplicate()
	var h: float = (m.z1 - m.z0) * 0.5
	c.z0 = -h
	c.z1 = h
	c.axis = Vector2.ZERO
	return c


static func _all_verts(objs: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for o in objs:
		out.append_array(o.verts)
	return out


func load_objects(spec: Dictionary) -> Array:
	if spec.has("parts"):
		return parts(spec.parts)
	var objs := []
	for f in spec.ac:
		var ac := read_ac(src.path_join(spec.get("dir", F16)).path_join(f))
		for o in ac.objects:
			if spec.get("drop", []).any(func(p): return String(o.name).begins_with(p)):
				continue
			o["mats"] = ac.mats
			if spec.has("livery") and o.tex != "":
				o.tex = fg.path_join(spec.livery)
			objs.append(o)
	return objs


## The Paveway II kits for the bomb `objs` (KIT_*): its shell's nose gets the guidance section, its aft body the tail.
func kit(objs: Array) -> Array:
	var shell := {}
	for o in objs:
		if String(o.name).ends_with("_Shell"):
			shell = o
	var sm := measure(shell.verts)
	var r_max := 0.0
	var z_max := 0.0
	for v in shell.verts:
		var r := Vector2(v.x, v.y).length()
		if r > r_max:
			r_max = r
			z_max = v.z
	var k := r_max / KIT_BODY_R
	var z_tail: float = sm.z1
	for v in shell.verts:
		if v.z > z_max and Vector2(v.x, v.y).length() >= KIT_TAIL_R * k:
			continue
		if v.z > z_max:
			z_tail = minf(z_tail, v.z)
	var ac := read_ac(fg.path_join("Armament").path_join(KIT_AC))
	var out := []
	for o in ac.objects:
		o["mats"] = ac.mats
		var x: Transform3D
		if o.name == KIT_BODY:
			var faces := []
			for fc in o.faces:
				if Array(fc.idx).all(func(j): return o.verts[j].z < KIT_SEAM):
					faces.append(fc)
			o.faces = faces
			x = Transform3D(Basis.IDENTITY, Vector3(0, 0, sm.z0 - KIT_SEAM))
		elif KIT_FRONT.any(func(p): return String(o.name).begins_with(p)):
			x = Transform3D(Basis.IDENTITY, Vector3(0, 0, sm.z0 - KIT_SEAM))
		elif KIT_TAIL.any(func(p): return String(o.name).begins_with(p)):
			x = Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(0, 0, z_tail - KIT_TAIL_Z * k))
		else:
			continue
		var w := PackedVector3Array()
		for v in o.verts:
			w.append(x * v)
		o.verts = w
		o.name = "kit_" + o.name
		out.append(o)
	return out


# --- our own stores --------------------------------------------------------------------------------------------


## Our procedural stores (no open model: the Python 5, the GBU-39 and its BRU-61/A, the SPICE kits, the Spike NLOS,
## the Popeye), in metres, nose at z 0 and aft +z, top +y, as objects like read_ac's. Each part is one of:
## - `lathe`: a body of revolution, [[z, r], …] (r 0 closes an end); `from` / `to` cut a band of it (its own colour),
##   `sq` its cross-section's superellipse exponent (2 round, higher squarer), `y` its axis' height;
## - `fins`: `n` plates around the axis from `roll` degrees (0 straight up), each [root z0, z1] at radius `r`, [tip
##   z0, z1] at radius `r` + `h`, `t` thick (thinner to the tip); `y` the axis' height;
## - `box`: [centre, size] (Vector3), `taper` its top's share of its bottom's width (1 a box).
## `rgb` its colour (sRGB, a material colour), `glass` true for the seeker glass (GLASS).
func parts(list: Array) -> Array:
	var out := []
	for i in list.size():
		var p: Dictionary = list[i]
		var o := {"name": "part%d" % i, "tex": "", "crease": 40.0, "faces": [], "verts": PackedVector3Array()}
		o["mats"] = [{"rgb": p.get("rgb", Color.WHITE), "trans": 1.0 if p.get("glass", false) else 0.0}]
		if p.has("lathe"):
			_lathe(o, _band(p.lathe, float(p.get("from", -INF)), float(p.get("to", INF))), p)
		elif p.has("fins"):
			for k in int(p.fins.get("n", 4)):
				_fin(o, p.fins, deg_to_rad(float(p.fins.get("roll", 0.0)) + 360.0 * k / int(p.fins.get("n", 4))))
		elif p.has("box"):
			_box(o, p.box[0], p.box[1], float(p.get("taper", 1.0)))
		out.append(o)
	return out


## The profile between z0 and z1, its ends interpolated.
static func _band(prof: Array, z0: float, z1: float) -> Array:
	var out := []
	for j in prof.size():
		var z: float = prof[j][0]
		if j > 0:
			var a: Array = prof[j - 1]
			for c in [z0, z1]:
				if a[0] < c and c < z:
					out.append([c, lerpf(a[1], prof[j][1], (c - a[0]) / (z - a[0]))])
		if z >= z0 and z <= z1:
			out.append(prof[j])
	return out


func _lathe(o: Dictionary, prof: Array, p: Dictionary) -> void:
	var n := int(p.get("n", 32))
	var e := 2.0 / float(p.get("sq", 2.0))
	var y := float(p.get("y", 0.0))
	for pt in prof:
		for j in n:
			var a := TAU * j / n
			var c := cos(a)
			var s := sin(a)
			var r := maxf(float(pt[1]), 0.0005)
			o.verts.append(Vector3(r * signf(c) * pow(absf(c), e), y + r * signf(s) * pow(absf(s), e), float(pt[0])))
	for i in prof.size() - 1:
		for j in n:
			var a := i * n + j
			var b := i * n + (j + 1) % n
			# Counter-clockwise seen from outside (AC's order; make_mesh turns it for Godot).
			o.faces.append(_face([a, b, b + n, a + n], true))


## A plate (fin, wing, canard) at angle `phi` around the axis (0 straight up, then towards +x).
func _fin(o: Dictionary, f: Dictionary, phi: float) -> void:
	var d := Vector3(sin(phi), cos(phi), 0)
	var side := Vector3(cos(phi), -sin(phi), 0)
	var y := Vector3(0, float(f.get("y", 0.0)), 0)
	var r := float(f.r)
	var h := float(f.h)
	var t := float(f.get("t", 0.008)) * 0.5
	var q := [[f.root[0], r, t], [f.root[1], r, t], [f.tip[1], r + h, t * 0.5], [f.tip[0], r + h, t * 0.5]]
	var pts := []
	for sgn in [1.0, -1.0]:
		for c in q:
			pts.append(y + d * float(c[1]) + side * float(c[2]) * sgn + Vector3(0, 0, float(c[0])))
	_solid(o, pts, [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]])


## A box (centre `c`, size `s`), its top `taper` of its bottom's width.
func _box(o: Dictionary, c: Vector3, s: Vector3, taper: float) -> void:
	var pts := []
	for k in 8:
		var top := k >= 4
		var x := s.x * 0.5 * (taper if top else 1.0) * (1 if k % 4 in [1, 2] else -1)
		pts.append(c + Vector3(x, s.y * (0.5 if top else -0.5), s.z * (0.5 if k % 4 >= 2 else -0.5)))
	_solid(o, pts, [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]])


## A convex solid's faces, each turned to face out (from the solid's centre).
func _solid(o: Dictionary, pts: Array, faces: Array) -> void:
	var base: int = o.verts.size()
	var mid := Vector3.ZERO
	for v in pts:
		o.verts.append(v)
		mid += v / pts.size()
	for f in faces:
		var n := Vector3.ZERO
		var fc := Vector3.ZERO
		for j in f.size():
			var a: Vector3 = pts[f[j]]
			var b: Vector3 = pts[f[(j + 1) % f.size()]]
			n += a.cross(b)
			fc += a / f.size()
		var idx: Array = f.map(func(k): return base + k)
		if n.dot(fc - mid) < 0.0:
			idx.reverse()
		o.faces.append(_face(idx, false))


static func _face(idx: Array, smooth: bool) -> Dictionary:
	var uv := PackedVector2Array()
	uv.resize(idx.size())
	return {"idx": PackedInt32Array(idx), "uv": uv, "mat": 0, "smooth": smooth}


# --- the mesh --------------------------------------------------------------------------------------------------


## One mesh of the objects (placed by `fit`): a surface per texture, every one textured (an untextured AC surface gets
## a white texel, its colour in the material) so every store draws with one shader. Every face is drawn from both sides
## (FlightGear marks them all two-sided; the material's culling is off and Godot flips the normal of a back face).
## Normals per corner: smooth faces share them with their smooth neighbours within the object's crease angle.
func make_mesh(objs: Array, fit: Transform3D, spec: Dictionary, target: int) -> ArrayMesh:
	var groups := {}  # texture path or "#rrggbb" -> SurfaceTool
	var crops := {}  # texture path -> Rect2 of the UVs used (livery only)
	for o in objs:
		if spec.has("livery") and o.tex != "":
			for fc in o.faces:
				for uv in fc.uv:
					var r := Rect2(uv, Vector2.ZERO)
					crops[o.tex] = crops[o.tex].merge(r) if crops.has(o.tex) else r
	for o in objs:
		var w := PackedVector3Array()
		for v in o.verts:
			w.append(fit * v)
		var fn := []
		var by_vert := {}
		for f in o.faces.size():
			var fc: Dictionary = o.faces[f]
			var n := Vector3.ZERO
			for j in fc.idx.size():  # Newell
				var a := w[fc.idx[j]]
				var b := w[fc.idx[(j + 1) % fc.idx.size()]]
				n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
			fn.append(n.normalized())
			if fc.smooth:
				for j in fc.idx:
					if not by_vert.has(j):
						by_vert[j] = []
					by_vert[j].append(f)
		var cos_c := cos(deg_to_rad(o.crease))
		var mat: Dictionary = o.mats[0] if o.mats.is_empty() == false else {"rgb": Color.WHITE, "trans": 0.0}
		for f in o.faces.size():
			var fc: Dictionary = o.faces[f]
			var md: Dictionary = o.mats[fc.mat] if fc.mat < o.mats.size() else mat
			var key: String = o.tex
			if key == "" or spec.get("glass", []).has(o.name):
				key = "#" + (GLASS.to_html(false) if md.trans > 0.0 or o.tex != "" else md.rgb.to_html(false))
			if not groups.has(key):
				groups[key] = SurfaceTool.new()
				groups[key].begin(Mesh.PRIMITIVE_TRIANGLES)
			var st: SurfaceTool = groups[key]
			var corners := []
			for j in fc.idx.size():
				var n: Vector3 = fn[f]
				if fc.smooth:
					var acc := Vector3.ZERO
					for g in by_vert[fc.idx[j]]:
						if fn[g].dot(fn[f]) >= cos_c:
							acc += fn[g]
					n = acc.normalized() if acc != Vector3.ZERO else n
				var uv: Vector2 = fc.uv[j]
				if crops.has(o.tex):
					var c: Rect2 = crops[o.tex]
					uv = (uv - c.position) / c.size
				corners.append([w[fc.idx[j]], n, uv if key[0] != "#" else Vector2(0.5, 0.5)])
			for t in range(1, corners.size() - 1):
				# AC faces are counter-clockwise; Godot's front faces clockwise.
				for c in [corners[0], corners[t + 1], corners[t]]:
					st.set_normal(c[1])
					st.set_uv(c[2])
					st.add_vertex(c[0])
	var mesh := ArrayMesh.new()
	var total := 0
	var arrays := {}
	for key in groups:
		var st: SurfaceTool = groups[key]
		st.index()
		arrays[key] = st.commit_to_arrays()
		total += arrays[key][Mesh.ARRAY_INDEX].size() / 3
	for key in arrays:
		var arr: Array = arrays[key]
		if target > 0 and total > target:
			arr = decimate(arr, arr[Mesh.ARRAY_INDEX].size() / 3 * target / total)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(key, crops, spec.get("tint", Color.WHITE)))
	var n_tris := 0
	for i in mesh.get_surface_count():
		n_tris += mesh.surface_get_array_index_len(i) / 3
	print("  %d triangles in %d surfaces" % [n_tris, mesh.get_surface_count()])
	return mesh


## The surface's arrays cut to about `tris` triangles (meshoptimizer's simplification through Godot's LOD generator:
## its first LOD at or under the count), vertices compacted.
static func decimate(arr: Array, tris: int) -> Array:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for l in im.get_surface_lod_count(0):
		idx = im.get_surface_lod_indices(0, l)
		if idx.size() / 3 <= tris:
			break
	var remap := {}
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var new_idx := PackedInt32Array()
	for i in idx:
		if not remap.has(i):
			remap[i] = pos.size()
			pos.append(arr[Mesh.ARRAY_VERTEX][i])
			nor.append(arr[Mesh.ARRAY_NORMAL][i])
			uv.append(arr[Mesh.ARRAY_TEX_UV][i])
		new_idx.append(remap[i])
	out[Mesh.ARRAY_VERTEX] = pos
	out[Mesh.ARRAY_NORMAL] = nor
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


## The surface's material: its texture (a livery cropped to `crops` and at most 512 px) times `tint`, or a white
## texel in its colour.
func material(key: String, crops: Dictionary, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.55
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var img: Image
	if key[0] == "#":
		img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		m.albedo_color = Color.html(key)
		if Color.html(key) == GLASS:
			m.roughness = 0.1
			m.metallic = 0.5
	else:
		img = Image.load_from_file(key)
		img.convert(Image.FORMAT_RGB8)
		m.albedo_color = tint
		if crops.has(key):
			var c: Rect2 = crops[key]
			var sz := Vector2(img.get_size())
			img = img.get_region(Rect2i(Vector2i((c.position * sz).floor()), Vector2i((c.size * sz).ceil())))
			var k := 512.0 / maxf(img.get_width(), img.get_height())
			if k < 1.0:
				img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	m.albedo_texture = ImageTexture.create_from_image(img)
	return m
