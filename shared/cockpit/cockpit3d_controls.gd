# Ours (Settings.cockpit_controls, Modern IAF; modern-iaf/docs/cockpit.md §5.1): the 3D cockpit's clickable controls. A
# cockpit's table, <model>_controls.json beside its model, binds the model's nodes to key commands:
#   {"<node>": {"click": [id, p1, p2], "turn": [id, p1, p2], "drag_px": 10, "prop": "<FlightGear property>",
#    "on": 2, "off": 0, "box": [x, y, z, w, h, d]}, ...}
#   - the node: a mesh of the model (its box, grown by REACH, is the hit area); a part merged into the model's body
#     has no node of its own: "box" (the model's frame, m: centre and size) is its hit area, lit when hovered; a box
#     with "grip": a part the model lacks, drawn as a grey rod along the box's length (_area);
#   - "click": sent on a left click (a switch);
#   - "prop", "on", "off": the switch's FlightGear property (its animation in <model>.json) and its two positions,
#     set by set_switch (cockpit3d.gd switches);
#   - "toggle": the switch flips its own "prop" between "on" and "off" on a click, with its click sound, and sends
#     "click" once every switch sharing that command is on (the F-16's AVIONIC POWER switches: each its own);
#   - "guard": a guarded switch's guard property (its cover's animation): while it is 0 a click only lifts the cover
#     (sets it to 1); the next click sends the switch's command, as the real guarded switch;
#   - "turn": sent on the wheel (up as it is, down with p1 negated) and once per drag_px of a left drag (up: as it is);
# through the key path (cockpit3d.gd `command`, terrain_view.gd _press), as the keys send them. Hovering a control
# lights its rim (RIM): its own texture stays as it is.
extends Node

## A control's hit area: its mesh's box grown this much (m) on each side.
const REACH := 0.004
## The pixels of a drag per "turn" command, unless the control sets its own.
const DRAG_PX := 10.0
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
var _hover: MeshInstance3D
var _held := {}  # the record under a left drag
var _drag := 0.0  # px dragged up since the last command
var _light: ShaderMaterial


## The controls of `table` found in `model`.
func setup(model: Node3D, table: Dictionary) -> void:
	for name in table:
		var r: Dictionary = table[name]
		var mi := model.find_child(name, true, false) as MeshInstance3D
		if mi == null and r.has("box"):
			mi = _area(name, r.box, r.get("grip", false))
			model.add_child(mi)
		if mi != null:
			_controls.append([mi, r])
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
		_held = {}  # released where this layer could not see it (a Control, the look's captured pointer)
		return
	_drag -= event.relative.y
	var px := float(_held.get("drag_px", DRAG_PX))
	while absf(_drag) >= px:
		_turn(_held, signf(_drag))
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
			_held = {}
			get_viewport().set_input_as_handled()
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and Settings.zoom_scrolling():
		return  # a zoom's scroll stays the zoom's when a knob comes under the pointer (Settings.zoom_steps)
	var hit = at(event.position)
	if hit == null:
		return
	var r: Dictionary = hit[1]
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if r.has("guard") and float(get_parent().switches.get(r.guard, 0.0)) < 0.5:
				get_parent().switches[r.guard] = 1.0  # the guard lifts; the switch moves on the next click
			elif r.get("toggle", false):
				_toggle(r)
			elif r.has("click"):
				get_parent().command.call(r.click)
			elif r.has("turn"):
				_held = r
				_drag = 0.0
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
	_held = {}
	return false


## The control under the viewport point `pos`: [its mesh, its record], of those whose box the view's ray crosses the
## one whose centre lies nearest the ray (the boxes overlap: the throttle's grip over the ELEC panel); null when none.
func at(pos: Vector2):
	var ray: Array = get_parent()._ray(pos)
	var best = null
	var best_d := INF
	for e in _controls:
		var mi: MeshInstance3D = e[0]
		var inv := mi.global_transform.affine_inverse()
		var box := mi.get_aabb()
		var hit = box.grow(REACH).intersects_ray(inv * ray[0], inv.basis * ray[1])
		if hit != null and mi.is_visible_in_tree():
			var c: Vector3 = mi.global_transform * box.get_center() - ray[0]
			var d: float = (c - c.project(ray[1])).length()
			if d < best_d:
				best_d = d
				best = e
	return best


## The switches sending command `id` on a click put to their "on" (else "off") position; a guarded one put on has its
## guard lifted.
func set_switch(id: int, on: bool) -> void:
	for e in _controls:
		var r: Dictionary = e[1]
		if r.has("prop") and int(r.get("click", [-1])[0]) == id:
			get_parent().switches[r.prop] = float(r.on if on else r.off)
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


## Flips toggle `r` alone (a switch FlightGear models unset counts as on: a hot jet's); once every switch of its
## command is on, sends the command (the checklist's step).
func _toggle(r: Dictionary) -> void:
	var sw: Dictionary = get_parent().switches
	var on := not _is_on(r)
	sw[r.prop] = float(r.on if on else r.off)
	var tv: Object = get_parent().command.get_object()  # terrain_view.gd (_press)
	if tv != null and tv.get("sounds") != null:
		tv.sounds.play("SFX_BUTTON")
	if on and _controls.all(func(e): return int(e[1].get("click", [-1])[0]) != int(r.click[0]) or _is_on(e[1])):
		get_parent().command.call(r.click)


func _is_on(r: Dictionary) -> bool:
	return float(get_parent().switches.get(r.prop, r.on)) == float(r.on)


func _turn(r: Dictionary, way: float) -> void:
	if not r.has("turn"):
		return
	var cmd: Array = r.turn.duplicate()
	cmd[1] = int(cmd[1] * way)
	get_parent().command.call(cmd)


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
