# Side-by-side comparison (not a test): the original HUD (left) and the Real HUD (right, Extras > HUD) on the same
# frames — top NAV cruise, bottom the MRM mode with a MiG locked 8 km ahead (mission 231, F-16 3000 m up with
# AMRAAMs). Writes hud_compare.png (each cell the HUD area, ×2). Usage:
#   SHOT_DIR=/tmp/shots IAF_DEFAULT_SETTINGS=1 godot --audio-driver Dummy --path game -s ../tests/godot/_hud_compare_shot.gd
extends "res://../tests/godot/base.gd"

const ZOOM := 2
const GAP := 8


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if DisplayServer.get_name() == "headless" or dir == "":
		print("needs a window and SHOT_DIR")
		return
	var tv = await start_mission(231)
	await frames(3)
	var w = airborne_case(tv, [8, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 1, 25, 235, 33, 90, 34, 60])
	var t := 1.0
	w.update(t)
	var rows := [await _pair(tv)]
	# The MRM mode with a lock.
	var o: Dictionary = w.own()
	var mig: Dictionary = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("mig23"))[0]
	mig.path = null
	mig.vel = Vector3.ZERO
	mig.world = o.pos + (o.sight.fwd if o.has("sight") else o.fwd) * 8000.0
	tv.mission_entity_moved(mig)
	w.radar_event(0x2b)
	w.update(t)
	w.radar_event(0x2a, mig.key)
	w.nav_key(0)
	w.stores.cur = 0
	w.select_aa()
	for i in 4:
		t += 0.05
		w.update(t)
	rows.append(await _pair(tv))
	var cw: int = rows[0][0].get_width()
	var ch: int = rows[0][0].get_height()
	var out := Image.create(2 * cw + GAP, rows.size() * ch + (rows.size() - 1) * GAP, false, Image.FORMAT_RGB8)
	out.fill(Color.BLACK)
	for r in rows.size():
		for c in 2:
			out.blit_rect(rows[r][c], Rect2i(0, 0, cw, ch), Vector2i(c * (cw + GAP), r * (ch + GAP)))
	out.save_png(dir.path_join("hud_compare.png"))
	print("RESULT PASS")


## [original, real] crops of the HUD area of the current frame.
func _pair(tv) -> Array:
	var out := []
	for style in ["original", "real"]:
		Settings().hud_style = style
		await frames(3)
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		var r: Rect2 = tv.cockpit.hud.get_global_rect().grow_individual(60, 25, 60, 45)
		var crop := img.get_region(Rect2i(r.position, r.size).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
		crop.convert(Image.FORMAT_RGB8)
		crop.resize(crop.get_width() * ZOOM, crop.get_height() * ZOOM, Image.INTERPOLATE_LANCZOS)
		out.append(crop)
	return out
