# Ours (Settings.cockpit_controls, Modern IAF; modern-iaf/docs/cockpit.md §5.1): the 3D cockpit's clickable controls. A
# cockpit's table, <model>_controls.json beside its model, binds the model's nodes to key commands:
#   {"<node>": {"click": [id, p1, p2], "turn": [id, p1, p2], "drag_px": 10, "prop": "<FlightGear property>",
#    "on": 2, "off": 0, "box": [x, y, z, w, h, d]}, ...}
#   - the node: a mesh of the model (its own surface is the hit area: the pointer finds the part its ray meets first,
#     never a neighbour's); a part merged into the model's body has no node of its own: "box" (the model's frame, m:
#     centre and size, fitted tight round the part) is its hit area, lit when hovered; a box
#     with "grip": a part the model lacks, drawn as a grey rod along the box's length (_area);
#   - "click": sent on a left click (a switch);
#   - "prop", "on", "off": the switch's FlightGear property (its animation in <model>.json) and its two positions,
#     set by set_switch (cockpit3d.gd switches);
#   - "toggle": the switch flips its own "prop" between "on" and "off" on a click, with its click sound, and sends
#     "click" with p1 1 on, -1 off (the F-16's AVIONIC POWER and SNSR PWR switches, command 219 with each its own p2:
#     sim_flight.gd system_switch);
#   - "modelled": the position the model shows while the switch is unset ("on" when not given: a hot jet's);
#   - "guard": a guarded switch's guard property (its cover's animation): while it is 0 a click only lifts the cover
#     (sets it to 1); the next click sends the switch's command, as the real guarded switch;
#   - "turn": sent on the wheel (up as it is, down with p1 negated) and once per drag_px of a left drag (up: as it is);
#     a control with "click" too takes a left press as a drag, and its release with no turn as the click (the INS
#     knob: a click and the wheel up turn it a position on, the wheel down a position back);
# through the key path (cockpit3d.gd `command`, terrain_view.gd _press), as the keys send them.
# Every other control comes from the model's own <model>.json `controls` (tools/f16d/cockpit3d.py control_of: the
# F-16's FlightGear bindings), the table's row laid over it where both name a node:
#   {"prop": "<property>", "mode": "cycle" | "slide" | "add" | "push", "min", "max", "step", "wrap", "modelled",
#    "rest", "press", "guard", "safe"}
#   - cycle (a switch or a knob of steps): a click the next position, the last going round to the first (as the INS
#     knob); the wheel and a drag a step on or back, stopping at the ends; with "rest" it springs: held at the
#     position the press chose (the next from rest) and back to rest when let go, the wheel's step back after SPRING_S;
#     with "spring" too (a list of positions) only those spring back, the others latch (the F-35I's IPP knob: START
#     springs back to AUTO, OFF stays);
#   - slide (a continuous knob, a wheel): the wheel and a drag a step either way, round past the ends only with "wrap";
#   - add (a button stepping a value, the ASI's bugs): a click adds its step;
#   - push (a push button): "press" while held, "rest" when let go;
#   - "guard": its cover's property (a control too): shut, a click lifts it first; shutting it puts the switch back to
#     "safe" (the F-16's EPU at NORM);
#   - "modelled": the position the model shows it at, its value until moved;
#   - "system" (a table row's, laid over the model's control): the game's system the control works (_system_put) and
#     shows (_system_state, each frame: a key moves the switch too).
# The position is kept in cockpit3d.gd `switches` (the one store of the cockpit's switches; the start-up's are the
# flight model's, start.rs) and shown by the model's own mapping. Hovering a control
# lights its rim (RIM): its own texture stays as it is. The flight controls are in neither table: the throttle and the
# stick move by the keys and the joystick's stick and throttle axes only, and animate with them (the user, 2026-11-15:
# "shouldn't be able to move the throttle or stick from the mouse"; until then the throttle grip took clicks, the wheel
# and drags, a drag down from idle over the detent to OFF).
extends Node

## The pixels of a drag per "turn" command, unless the control sets its own.
const DRAG_PX := 10.0
## A spring-loaded switch moved by the wheel stays this long before it springs back (s, inferred).
const SPRING_S := 0.4
## The hover's overlay: a faint cool white laid thinly over the part and thicker where its surface turns away from the
## eye, a rim light that leaves the part's own colour and texture showing (the user, 2026-11-11: the warm fill "is too
## yellowish and loses the texture of the wheel"; the colour and strengths are inferred). A mix, not an add: the
## cockpit's picture is composited by its alpha (cockpit_composite.gdshader), which an add would push past 1.
const RIM := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, fog_disabled;
void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = vec3(0.8, 0.9, 1.0);
	ALPHA = 0.06 + 0.3 * pow(edge, 4.0);
}
"""

var _controls := []  # [MeshInstance3D, its record]
var _shapes := {}  # MeshInstance3D -> its surface (TriangleMesh, the mesh's frame in mm): the hit area
## The surfaces' scale (mm per m): Godot's ray-triangle test takes a triangle a few mm across as parallel to every ray
## (its fixed epsilon, Geometry3D ray_intersects_triangle), so the switches' surfaces are kept in millimetres.
const MM := 1000.0
var _hover: MeshInstance3D
var _held := {}  # the record under a left drag
var _drag := 0.0  # px dragged up since the last command
var _turned := false  # the held control turned since its press (else its release clicks)
var _light: ShaderMaterial


## The controls of `table` and of the model's own `generic` (<model>.json `controls`) found in `model`; a table row
## laid over the model's record of the same node.
func setup(model: Node3D, table: Dictionary, generic := {}) -> void:
	var all := generic.duplicate()
	for name in table:
		all[name] = generic.get(name, {}).merged(table[name], true)
	var sw: Dictionary = get_parent().switches
	for name in all:
		var r: Dictionary = all[name]
		if r.has("modelled") and not r.has("on") and not sw.has(r.prop):
			sw[r.prop] = float(r.modelled)  # a switch the flight model does not hold starts as the model shows it
		var mi := model.find_child(name, true, false) as MeshInstance3D
		if mi == null and r.has("box"):
			mi = _area(name, r.box, r.get("grip", false))
			model.add_child(mi)
		if mi != null:
			_controls.append([mi, r])
			var faces := mi.mesh.get_faces()
			var xf := Transform3D.IDENTITY.scaled(Vector3.ONE * MM)
			if mi.get_child_count() > 0 and mi.get_child(0) is MeshInstance3D:  # a box's grip: the rod alone (_area)
				faces = mi.get_child(0).mesh.get_faces()
				xf = xf * mi.get_child(0).transform
			for i in faces.size():
				faces[i] = xf * faces[i]
			_shapes[mi] = TriangleMesh.new()
			_shapes[mi].create_from_faces(faces)
	_light = ShaderMaterial.new()
	_light.shader = Shader.new()
	_light.shader.code = RIM


## The pointer's moves, before the GUI: a control under it lights, a drag turns the held one. (The flight's full-view
## Controls take every move over them, so _unhandled_input would see none.)
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion and _live()):
		return
	if _held.is_empty():
		var hit = at(event.position)
		_highlight(hit[0] if hit != null else null)
		return
	if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drop()  # released where this layer could not see it (a Control, the look's captured pointer)
		return
	_drag -= event.relative.y
	var px := float(_held.get("drag_px", DRAG_PX))
	while absf(_drag) >= px:
		_turn(_held, signf(_drag), true)
		_drag -= signf(_drag) * px
	get_viewport().set_input_as_handled()


## The clicks and the wheel no Control took.
func _unhandled_input(event: InputEvent) -> void:
	if not _live():
		return
	if not event is InputEventMouseButton:
		return
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _held.is_empty():
			release()
			get_viewport().set_input_as_handled()
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and Settings.zoom_scrolling():
		return  # a zoom's scroll stays the zoom's when a knob comes under the pointer (Settings.zoom_steps)
	var hit = at(event.position)
	if hit == null:
		hit = _lit()  # the lit part: a lever turned by the wheel slides out from under a still pointer
	if hit == null:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not _wheeled(hit[1]):
		return  # a switch takes no wheel: the view's zoom has it
	# The part acted on is the lit one: a lever thrown by this click (the HUD's DAY / AUTO BRT / NIGHT switch) moves out
	# from under a still pointer, and the next wheel step still turns it rather than zooming the view (2026-11-16: a
	# click with no hover before it left nothing lit, and the wheel after it zoomed).
	_highlight(hit[0])
	var r: Dictionary = hit[1]
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if r.has("guard") and float(get_parent().switches.get(r.guard, 0.0)) < 0.5:
				get_parent().switches[r.guard] = 1.0  # the guard lifts; the switch moves on the next click
			elif _generic(r) or r.get("mode", "") == "push":
				press(r)
			elif r.get("toggle", false):
				_toggle(r)
			elif r.has("turn"):
				_held = r
				_drag = 0.0
				_turned = false
			elif r.has("click"):
				get_parent().command.call(r.click)
		MOUSE_BUTTON_WHEEL_UP:
			_turn(r, 1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_turn(r, -1.0)
		_:
			return
	get_viewport().set_input_as_handled()


## The cockpit in view and the pointer free (not looking about: terrain_view.gd's right button); else nothing lit
## or held.
func _live() -> bool:
	var c3d := get_parent()
	if (
		c3d.camera != null
		and c3d.camera.current
		and c3d.is_visible_in_tree()
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		return true
	_highlight(null)
	_drop()
	return false


## The control under the viewport point `pos`: [its mesh, its record], the one whose surface the view's ray meets
## nearest the eye (the user, 2026-11-15: the hit area the part's own shape, never bigger, never a neighbour's; until
## then each part's box grown by 4 mm, the nearest centre of those crossed); null when none.
func at(pos: Vector2):
	var ray: Array = get_parent()._ray(pos)
	var best = null
	var best_d := INF
	for e in _controls:
		var mi: MeshInstance3D = e[0]
		if not mi.is_visible_in_tree():
			continue
		var inv := mi.global_transform.affine_inverse()
		var hit: Dictionary = _shapes[mi].intersect_ray(inv * ray[0] * MM, inv.basis * ray[1])
		if hit.is_empty():
			continue
		var d: float = ray[1].dot(mi.global_transform * (hit.position / MM) - ray[0])
		if d < best_d:
			best_d = d
			best = e
	return best


## The switches sending command `id` on a click put to their "on" (else "off") position, or to `value` (a knob's
## position, FlightGear's value: the INS knob's 0..5) when given; a guarded one put on has its guard lifted.
func set_switch(id: int, on: bool, p2 := -1, value := NAN) -> void:
	for e in _controls:
		var r: Dictionary = e[1]
		var click: Array = r.get("click", [-1, 0, 0])
		# A switch with a "system" shows its system's own position (sync).
		if r.has("prop") and int(click[0]) == id and (p2 < 0 or int(click[2]) == p2) and not r.has("system"):
			get_parent().switches[r.prop] = value if not is_nan(value) else float(r.on if on else r.off)
			if on and r.has("guard"):  # thrown by its key or the throttle: its guard up too, not shut over the bat
				get_parent().switches[r.guard] = 1.0


## A hit area of `box` [centre, size] (m, the model's frame): a box drawn clear, lit by the hover's overlay. With
## `grip` it holds a grey metal rod, as thick as the box is narrow, along its depth (z): the F-16's canopy handle,
## which FlightGear's model lacks (the Mac play test's finding 11: the clear box alone showed nothing). Grey, not
## black, so it shows on the black canopy sill (its finish is inferred). The box around a rod is drawn on no layer:
## the hover lights the rod's rim, not the box's faces.
static func _area(name: String, box: Array, grip := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(box[3], box[4], box[5])
	mi.mesh = mesh
	mi.position = Vector3(box[0], box[1], box[2])
	var clear := StandardMaterial3D.new()
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.albedo_color = Color(0, 0, 0, 0)
	mi.material_override = clear
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if grip:
		var rod := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = minf(box[3], box[4]) / 2.0
		cap.height = box[5]
		rod.mesh = cap
		rod.rotation = Vector3(PI / 2.0, 0.0, 0.0)  # the capsule's length (y) along z
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.45, 0.45, 0.45)
		metal.metallic = 0.6
		metal.roughness = 0.4
		rod.material_override = metal
		mi.add_child(rod)
		mi.layers = 0
	return mi


## Flips toggle `r` alone (a switch FlightGear models unset counts as on: a hot jet's) and sends its command with p1 1
## on, -1 off (the flight model may refuse it: sim_flight.gd _set_switch shows it back).
func _toggle(r: Dictionary) -> void:
	var sw: Dictionary = get_parent().switches
	var on := not _is_on(r)
	sw[r.prop] = float(r.on if on else r.off)
	var tv: Object = get_parent().command.get_object()  # terrain_view.gd (_press)
	if tv != null and tv.get("sounds") != null:
		tv.sounds.play("SFX_BUTTON")
	if r.has("click"):
		get_parent().command.call([r.click[0], 1 if on else -1, r.click[2]])


func _is_on(r: Dictionary) -> bool:
	return float(get_parent().switches.get(r.prop, r.get("modelled", r.on))) == float(r.on)


## Turns `r` a step (`way` 1 up, −1 down) by the wheel, or by the held control's left drag (`drag`).
func _turn(r: Dictionary, way: float, drag := false) -> void:
	if drag:
		_turned = true
	if _generic(r):
		_step(r, way)
		return
	if not r.has("turn"):
		return
	var cmd: Array = r.turn.duplicate()
	cmd[1] = int(cmd[1] * way)
	get_parent().command.call(cmd)


## A control of the model's own `controls` alone: moved here, no command (a table row's "click", "turn" or "toggle"
## sends its own).
static func _generic(r: Dictionary) -> bool:
	return r.has("mode") and (r.has("system") or not (r.has("click") or r.has("turn") or r.has("toggle")))


## Whether `r` takes the wheel: a table row's "turn", a continuous knob, a stepping button, a rotary of four positions
## or more; a switch (up to three) leaves the wheel to the view's zoom and goes both ways by its drag.
static func _wheeled(r: Dictionary) -> bool:
	if r.has("turn") or (_generic(r) and r.mode in ["slide", "add"]):
		return true
	return _generic(r) and r.mode == "cycle" and (float(r.max) - float(r.min)) / float(r.step) >= 2.5


## The left press on `r` (the pointer's, or a test's): a push button or a spring-loaded switch moves at once and is
## held; any other is held for a drag, its release with no turn its click. Under a shut cover: the cover lifts.
func press(r: Dictionary) -> void:
	if r.has("guard") and float(get_parent().switches.get(r.guard, 0.0)) < 0.5:
		get_parent().switches[r.guard] = 1.0  # its cover lifts; the switch moves on the next press
		return
	_held = r
	_drag = 0.0
	_turned = false
	if r.get("mode", "") == "push":
		put(r, float(r.press))
	elif r.has("rest") and r.get("mode", "") == "cycle":
		var n := _next(r, value(r) if r.has("spring") else float(r.rest))
		if _springs(r, n):  # else a latched position: the release's click moves it
			put(r, n)


## The left button let go over the held control: a push button or a spring back to rest; a press with no turn clicks.
func release() -> void:
	var r := _held
	_held = {}
	if r.is_empty():
		return
	if not _generic(r):
		if r.get("mode", "") == "push":  # a push button with a command: back up, the command on its release
			put(r, float(r.rest))
		if not _turned and r.has("click"):
			get_parent().command.call(r.click)
		return
	if _springs(r, value(r)):
		put(r, float(r.rest))
	elif not _turned:
		match r.mode:
			"cycle":
				put(r, _next(r, value(r)))
			"add":
				_step(r, signf(float(r.step)))


## The held control let go unseen: a push button or a spring back to rest, no click.
func _drop() -> void:
	if _held.has("prop") and _springs(_held, value(_held)):
		put(_held, float(_held.rest))
	_held = {}


## The position of control `r` now (as modelled until moved).
func value(r: Dictionary) -> float:
	return float(get_parent().switches.get(r.prop, r.get("modelled", 0.0)))


## The position after `v` for a click: the next step, the last going round to the first.
static func _next(r: Dictionary, v: float) -> float:
	var n := v + absf(float(r.step))
	return float(r.min) if n > float(r.max) + 1e-4 else n


## `r` a step on (`way` 1) or back (−1): stopping at the ends, or round with "wrap" (not a switch's: its round is the
## click's); a spring's step held SPRING_S, then back to rest.
func _step(r: Dictionary, way: float) -> void:
	var lo := float(r.get("min", 0.0))
	var hi := float(r.get("max", 1.0))
	var st := absf(float(r.get("step", 1.0)))
	if r.get("mode", "") == "push":
		return
	if r.has("rest") and not r.has("spring"):
		put(r, clampf(float(r.rest) + way * st, lo, hi))
		get_tree().create_timer(SPRING_S).timeout.connect(_spring.bind(r))
		return
	var v := value(r) + way * st
	if r.get("wrap", false) and r.mode != "cycle":
		v = lo + fposmod(v - lo, hi - lo)
	v = clampf(snappedf(v, st * 1e-3), lo, hi)
	put(r, v)
	if _springs(r, v):
		get_tree().create_timer(SPRING_S).timeout.connect(_spring.bind(r))


## A spring's wheel or drag step back to rest, unless it is held.
func _spring(r: Dictionary) -> void:
	if _held != r and _springs(r, value(r)):
		put(r, float(r.rest))


## Whether `r` springs back to rest from position `v`: any position of a spring-loaded control, or only those of its
## "spring" list.
static func _springs(r: Dictionary, v: float) -> bool:
	if not r.has("rest"):
		return false
	if not r.has("spring"):
		return true
	return (r.spring as Array).any(func(p): return is_equal_approx(float(p), v))


## Control `r` to `v` in the store, with its click; a guard shut puts the switches under it back to their safe place.
func put(r: Dictionary, v: float) -> void:
	var sw: Dictionary = get_parent().switches
	if is_equal_approx(float(sw.get(r.prop, NAN)), v):
		return
	var was := value(r)
	sw[r.prop] = v
	var tv: Object = get_parent().command.get_object() if get_parent().command.is_valid() else null
	if tv != null and tv.get("sounds") != null:
		tv.sounds.play("SFX_BUTTON")
	if r.has("system"):
		_system_put(r.system, v, was)
	if v < 0.5:
		for e in _controls:
			if e[1].get("guard", "") == r.prop and e[1].has("safe") and _generic(e[1]):
				sw[e[1].prop] = float(e[1].safe)


## The start-up switches of three positions (f16_controls.json `system`) and their command [id, p2]: MAIN PWR 210,
## the JFS 211, RDR ALT 219 with its index in sim_flight.gd SYSTEMS.
const START_CMD := {"main_power": [210, 0], "starter": [211, 0], "rdr_alt": [219, 5]}
## The F-35I's BATT (RESET / OFF / ON) and ENGINE (OFF / MOTOR / NORM): their command and the position over which they
## are on; MOTOR and RESET move the switch only (motoring and the battery's reset are not modelled).
const F35_START := {"batt": [210, 0.5], "eng": [212, 1.5]}

# The switches wired to the systems the game has (a row's "system", finish list C2; modern-iaf/docs/cockpit.md §5.2):
# a move sends the system's own command through the key path (or sets its state), and each frame the switch shows the
# system's state, so a key moves the switch too. A system the game lacks leaves its switch a moving part only.


## Each frame: every switch with a "system" not held shown at that system's state (_system_state).
func sync() -> void:
	var tv: Object = get_parent().command.get_object() if get_parent().command.is_valid() else null
	if tv == null or tv.get("weapons") == null:
		return
	var sw: Dictionary = get_parent().switches
	for e in _controls:
		var r: Dictionary = e[1]
		if r.has("system") and _held != r:
			var v := _system_state(tv, r.system, value(r))
			if not is_nan(v):
				sw[r.prop] = v


## System `name`'s state as its switch's position (`now` the switch's own); NAN: the switch keeps its own.
static func _system_state(tv: Object, name: String, now: float) -> float:
	match name:
		"master_arm":  # SIMULATE / OFF / MASTER ARM: safe keeps SIMULATE (not modelled) or OFF
			return 1.0 if tv.weapons.master_arm else minf(now, 0.0)
		"mfd_brt":
			return Settings.mfd_brightness
		"alt_flaps":
			return 1.0 if float(tv.flaps) > 0.0 else 0.0
		"stores_config":
			return 1.0 if tv.cat3 else 0.0
		"mpo":
			return 1.0 if tv.mpo or tv.mpo_on else 0.0
		"main_power", "starter", "rdr_alt":  # the flight model's (start.rs Start::position)
			return float(tv.flight.start_position(name)) if tv.flight != null else NAN
		"batt":  # the F-35I's BATT RESET (-1) / OFF / ON: off keeps RESET or OFF
			if tv.flight != null:
				return 1.0 if tv.flight.start_on("main_power") else minf(now, 0.0)
		"eng":  # the F-35I's ENGINE OFF / MOTOR / NORM: not running keeps MOTOR or OFF
			if tv.flight != null:
				return 2.0 if tv.flight.start_on("engine") else (1.0 if is_equal_approx(now, 1.0) else 0.0)
	return NAN


## Switch of system `name` moved to `v` from `was`: the system's command (terrain_view.gd _press, as the key sends it)
## or state.
func _system_put(name: String, v: float, was := NAN) -> void:
	var cmd: Callable = get_parent().command
	if name in F35_START:  # a command as the switch moves into or out of its on position: p1 1 on, -1 off
		var at: float = F35_START[name][1]
		if is_nan(was) or (v > at) != (was > at):
			cmd.call([F35_START[name][0], 1 if v > at else -1, 0])
		return
	if name in START_CMD:  # the start-up switches of three positions: p1 -1 OFF, 2 the in-between position, 1 on
		var p := roundi(v)
		var mid := -1 if name == "starter" else 1  # START 1, BATT, STBY
		cmd.call([START_CMD[name][0], -1 if p == 0 else (2 if p == mid else 1), START_CMD[name][1]])
		return
	var tv: Object = cmd.get_object() if cmd.is_valid() else null
	if tv == null or tv.get("weapons") == null:
		return
	var on := v > 0.5
	match name:
		"master_arm":  # command 202 flips it
			if on != tv.weapons.master_arm:
				tv._press([202, 0, 0])
		"emer_jett":  # the push: command 72
			if on:
				tv._press([72, 0, 0])
		"a_a", "a_g":  # the ICP's A-A / A-G: commands 62 / 60
			if on:
				tv._press([62 if name == "a_a" else 60, 0, 0])
		"mfd_brt":  # command 216: thousandths up or down
			tv._press([216, roundi((v - Settings.mfd_brightness) * 1000.0), 0])
		"hmd_brt", "mfd_step":  # the F-35I's spring-loaded BRT rockers: a step (2.5 %) up or down as they are pushed
			if absf(v) > 0.5:
				tv._press([123 if name == "hmd_brt" else 216, 25 * int(signf(v)), 0])
		"ipp_start":  # the F-35I's IPP knob turned to START (its last position): the engine start, as the key's
			if v > 1.5:
				tv._press([212, 1, 0])
		"alt_gear":  # the F-35I's ALT GEAR EXTENSION: the gear down when it is up (command 14 moves the lever)
			if on and not tv.gear_down:
				tv._press([14, 0, 0])
		"alt_flaps":  # command 12 flips the flaps lever
			if on != (float(tv.flaps) > 0.0):
				tv._press([12, 0, 0])
		"stores_config":
			tv.cat3 = on
		"mpo":
			tv.mpo = on
		"hmcs":  # the HMCS SYM INT knob: OFF takes the helmet display's power
			tv.cockpit.helmet_power = v > 0.0
		"lamp_test":  # MAL & IND LTS: every lamp lit while held
			tv.cockpit_3d.lamp_test = on
		"master_caution":  # the push-light: the MASTER CAUTION lamp out until the next caution
			if on:
				tv.cockpit.indicators[0] = false


## The control lit under the pointer ([its mesh, its record]), null when none: it keeps the clicks and the wheel until
## the pointer moves off it, so a lever moved by its own click or wheel step (the HUD's DAY / AUTO BRT / NIGHT switch)
## still takes the next one.
func _lit():
	for e in _controls:
		if e[0] == _hover and is_instance_valid(_hover) and _hover.is_visible_in_tree():
			return e
	return null


func _highlight(mi: MeshInstance3D) -> void:
	if mi == _hover:
		return
	if is_instance_valid(_hover):
		_overlay(_hover, null)
	_hover = mi
	if mi != null:
		_overlay(mi, _light)


## Lays `m` over `mi` and its child meshes (the canopy handle's rod, drawn by _area; no model control has any).
static func _overlay(mi: MeshInstance3D, m: Material) -> void:
	mi.material_overlay = m
	for c in mi.get_children():
		if c is MeshInstance3D:
			c.material_overlay = m
