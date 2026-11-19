# Dev helper (not run by tools/test.sh): the missile warning's pictures (modern-iaf/docs/ews.md §3), per jet on its
# weapons range ahead of Drones 4 (the F-35 pair with radars on, locking the jet), the Graphics preset "Everything on":
# a drone launches a radar-guided missile (an AIM-120, kind 600), then an infrared one (an AIM-9X, kind 570) at the jet.
# - the Sufa and the Barak: <unit>_<kind>_rwr.png, the 3D cockpit's RWR scope face (its 256 px, scaled 3x);
# - the Adir: f35i_<kind>_twd.png and f35i_<kind>_das.png (portal 0 cropped from the PCD's glass, 1920 wide) and
#   f35i_<kind>_helmet.png (the frame looking ahead).
# SHOT_JETS=f16i,f35i picks the jets. A real render: run it hidden, one at a time,
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_missile_warning_shot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const JETS := {"f16i": "ramon_range", "f16d": "ramat_david_range", "f35i": "nevatim_range"}
const KINDS := {"radar": 600, "ir": 570}


## A missile flying at the jet, as the RWR's list keeps it (player_weapons.gd _rwr_missile's "m").
class FakeMissile:
	extends RefCounted
	var p0: Vector3
	var v: Vector3
	var t0: float

	func position(now: float) -> Vector3:
		return p0 + v * (now - t0)

	func velocity(_now: float) -> Vector3:
		return v


var dir := ""
var tv: Node
var w
var c


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var only := OS.get_environment("SHOT_JETS")
	for unit in JETS:
		if only == "" or unit in only.split(","):
			await _jet(unit)


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


## 15 km ahead of the pair, head on: the drones' radars see the jet and lock it.
func _ahead(dr) -> void:
	var st: Dictionary = dr.state()
	_put(st.position + st.velocity.normalized() * 15000.0, -st.velocity, float(st.heading) + 180.0)


func _jet(unit: String) -> void:
	var s := settings()
	var id := sim_mission(JETS[unit])
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("mw-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	tv.views.snap = Vector2.ZERO
	var dr = tv.ai.pilots.filter(func(q): return String(q.ent.name).begins_with("Drones 4"))[0]
	_ahead(dr)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not c.ews.get("symbols", []).any(func(x): return x.label == "35"):
		await fly(tv, 0.5)
	var n := 9300
	for kind in KINDS:
		_ahead(dr)
		await fly(tv, 0.5)
		var o: Dictionary = w.own()
		var m := FakeMissile.new()
		var d: Vector3 = o.fwd.rotated(Vector3(0, 0, 1), -0.25)
		m.p0 = o.pos + d * 9000.0
		m.v = -d * 700.0
		m.t0 = w.now
		n += 1
		w.rwr.launch(String(dr.ent.key), {"id": n, "pos": m.p0, "decoy": false, "m": m, "weapon": KINDS[kind]})
		await fly(tv, 0.6)
		print("%s %s: symbols %s maw %s" % [unit, kind, c.ews.get("symbols", []), c.ews.get("maw", [])])
		if unit == "f35i":
			await _portal("%s_%s_twd" % [unit, kind], "TWD")
			await _portal("%s_%s_das" % [unit, kind], "DAS")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(dir.path_join("%s_%s_helmet.png" % [unit, kind]))
		else:
			await _scope("%s_%s_rwr" % [unit, kind])
		w.rwr.missile_end(String(dr.ent.key), {"id": n, "m": m})
		await fly(tv, 1.0)
	tv.queue_free()
	await frames(5)


## The flashing symbols (a launch, the MAW's M) in their lit half: the RWR scope's 167 ms phases, the PCD's 300 ms.
func _lit(ms: int) -> void:
	while Time.get_ticks_msec() % (2 * ms) > ms / 4:
		await process_frame


func _scope(name: String) -> void:
	var scope = tv.cockpit_3d.displays.get("RWR_scope")
	await _lit(167)
	scope.queue_redraw()
	await RenderingServer.frame_post_draw
	var img: Image = (scope.get_parent() as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_LANCZOS)
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name, " ", scope.shown)


func _portal(name: String, f: String) -> void:
	var pcd = c.pcd
	pcd._show(0, f)
	await fly(tv, 0.5)
	await _lit(300)
	await RenderingServer.frame_post_draw
	var img: Image = (pcd.get_parent() as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var r: Rect2 = pcd.portals()[0]
	var crop := img.get_region(Rect2i(r.position.floor(), r.size.ceil()))
	crop.resize(1920, int(1920.0 * crop.get_height() / crop.get_width()), Image.INTERPOLATE_LANCZOS)
	crop.save_png(dir.path_join(name + ".png"))
	print("shot ", name)
