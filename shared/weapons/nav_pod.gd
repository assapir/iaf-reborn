# Ours, Modern IAF's F-16s: the navigation pod on 5L (modern-iaf/docs/weapons.md §7.4; research/pods.md P7, P8): the
# LANTIRN AN/AAQ-13 (the Sufa: a FLIR and a terrain-following radar) or the Pathfinder (the Barak: the FLIR only). The
# FLIR's power, warm-up and STBY / OPER; its picture on the HUD (shared/cockpit/hud_flir.gdshader) with the FLIR
# format's polarity, gain and level, snap-look (the cursor with the HUD the SOI) and look-into-turn; the TFR's settings,
# ADV MODE, MANUAL TF FLYUP, the paddle, the fly-ups and the pitch it flies. The logic is iaf_avionics::nav_pod through
# IafNavPod.
extends RefCounted

## The 3D cockpit's ADV MODE button and the MISC panel's RF switch (FlightGear's properties: 0 NORM, 1 QUIET, 2
## SILENT; the model rests at QUIET, cockpit3d.gd starts it at NORM).
const ADV := "f16/fcs/adv-mode-sel"
const RF := "f16/avionics/rf/rf-switch"
const RF_MODELLED := 1.0
## The FLIR format's gain steps and level step (ours).
const GAINS := [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
const LEVEL_STEP := 0.1
const LEVEL_MAX := 0.5
## Snap-look's shift (degrees across, up; ours) and look-into-turn's: this share of the bank, at most TURN_MAX_DEG
## (ours).
const SNAP_DEG := Vector2(20.0, 10.0)
const TURN_K := 0.15
const TURN_MAX_DEG := 10.0
const HUD_FLIR := "res://shared/cockpit/hud_flir.gdshader"

var weapons: Node  # player_weapons.gd
## 0 none, 1 the Pathfinder (the FLIR), 2 the LANTIRN (the FLIR and the TFR).
var kind := 0
## When the pod got its power (NAN none; a jet powered in the air, or from the start, has it warm).
var power_at := NAN
var flir_stby := true
var black_hot := false
var gain_i := 2
var level := 0.0
## Snap-look's held direction (the cursor keys' signs, y up), zero when let go.
var snap := Vector2.ZERO
## The FLCS panel's MANUAL TF FLYUP (at DISABLE until set: no manual fly-up on take-off, ours); ADV MODE and the RF
## switch without the 3D cockpit. The stick's paddle switch (held, Shift + I) is the autopilot's too: one switch.
var man_flyup := false
var paddle: bool:
	get:
		return bool(weapons.host.get("ap_paddle"))
var adv := false
var rf := 0
## IafNavPod.step's last output ({} none).
var out := {}
var _pod = ClassDB.instantiate("IafNavPod")
var _picture: ColorRect
var _seen := false
var _fly_up := ""
var _profile := []  # the terrain ahead against the jet's altitude (m), for the TFR format's E-scope


func _init(w: Node, names: Array) -> void:
	weapons = w
	kind = 2 if "NVP" in names else (1 if "PATH" in names else 0)


func tfr() -> bool:
	return kind == 2


## The FLIR's state (IafNavPod.flir_state): 0 off, 1 warming up, 2 STBY, 3 OPER.
func flir_state() -> int:
	var on: float = -1.0 if is_nan(power_at) else weapons.now - power_at
	return _pod.flir_state(on, flir_stby)


func _switches() -> Variant:
	var c3 = weapons.host.get("cockpit_3d")
	return c3.switches if c3 != null else null


func adv_on() -> bool:
	var s = _switches()
	return float(s.get(ADV, 0.0)) > 0.5 if s != null else adv


func rf_pos() -> int:
	var s = _switches()
	return int(round(float(s.get(RF, RF_MODELLED)))) if s != null else rf


## ADV MODE (key, or the 3D cockpit's button): automatic TF selected or not.
func adv_key() -> void:
	var s = _switches()
	if s != null:
		s[ADV] = 0.0 if adv_on() else 1.0
	else:
		adv = not adv


## The TFR format's OSBs: 0 the mode, 1 the SCP, 2 the ride.
func next_setting(what: int) -> void:
	_pod.next_setting(what)


func settings() -> Dictionary:
	return _pod.settings(rf_pos())


## The FLIR format's OSBs: the gain a step up / down, the level a step up / down.
func step_gain(up: bool) -> void:
	gain_i = clampi(gain_i + (1 if up else -1), 0, GAINS.size() - 1)


func step_level(up: bool) -> void:
	level = clampf(level + (LEVEL_STEP if up else -LEVEL_STEP), -LEVEL_MAX, LEVEL_MAX)


## Per weapons update: the power, the TFR's step, the fly-up's voice and the HUD picture.
func update() -> void:
	var up: bool = weapons._up("mmc") and weapons._up("l_hdpt")  # LEFT HDPT's power (start.rs SYSTEMS)
	var o: Dictionary = weapons.own()
	if not up:
		power_at = NAN
	elif is_nan(power_at):
		power_at = weapons.now if _seen and o.wow else -1.0e6
	_seen = true
	if tfr():
		_step_tfr(up, o)
	_update_picture()


func _step_tfr(up: bool, o: Dictionary) -> void:
	var host: Node = weapons.host
	var st: Dictionary = host.flight.state() if host.flight != null else {}
	var pos: Vector3 = o.pos
	var v: Vector3 = o.vel
	var dir := Vector2(v.x, v.y)
	dir = dir.normalized() if dir.length() > 1.0 else Vector2(o.fwd.x, o.fwd.y).normalized()
	var profile := []
	var step: float = _pod.profile_step()
	for k in int(_pod.profile_samples()):
		var p := Vector2(pos.x, pos.y) + dir * step * (k + 1)
		profile.append(host.mission_ground(Vector3(p.x, p.y, 0.0)))
	_profile = profile.map(func(h): return null if h == null else float(h) - pos.z)
	var g = host.mission_ground(pos)
	var input := {
		"agl_m": pos.z - float(g) if g != null else 1.0e4,
		"alt_m": pos.z,
		"tas_ms": v.length(),
		"gamma_deg": rad_to_deg(asin(clampf(v.z / maxf(v.length(), 1.0), -1.0, 1.0))),
		"roll_deg": float(st.get("roll", 0.0)),
		"kcas": float(st.get("cas_kt", 0.0)),
		"gear_down": bool(st.get("gear_down", false)),
		"profile": profile
	}
	var sw := {"powered": up, "rf": rf_pos(), "adv": adv_on(), "man_flyup": man_flyup, "paddle": paddle}
	out = _pod.step(input, sw, weapons._dt)
	# The fly-up's voice once as it starts (research/pods.md §3.3: PULL-UP in the voice; the GAAF's call).
	var f := String(out.fly_up)
	if f != "" and _fly_up == "" and host.get("sounds") != null:
		host.sounds.play("VOC_BBETTY", "BTY_PULL_UP")
	_fly_up = f


## The pitch (and with TF FAIL the roll) the TFR flies this frame, from the pilot's `stick` (terrain_view.gd, before
## the flight model takes it); the pilot's own pitch adds to the TFR's.
func fly(stick: Vector2, dt: float, g: float) -> Vector2:
	if out.is_empty() or not tfr():
		return stick
	var y: float = _pod.stick(float(out.g_cmd), g, 0.0, dt)
	if not out.flies:
		return stick
	var s := Vector2(stick.x, clampf(y + stick.y, -1.0, 1.0))
	if String(out.fly_up) == "TF FAIL":
		s.x = _pod.level_wings(_roll())
	return s


## The HUD's TF cues (real_hud.rs panel "tf"), null while the TFR does not work.
func hud_tf() -> Variant:
	return out.tf if tfr() and not out.is_empty() and out.operating else null


## The picture shifted (snap-look held, or look-into-turn past a degree): the flight path marker dashed.
func picture_shift_deg() -> Vector2:
	var roll := _roll()
	var turn := clampf(roll * TURN_K, -TURN_MAX_DEG, TURN_MAX_DEG)
	return Vector2(snap.x * SNAP_DEG.x + turn, snap.y * SNAP_DEG.y)


func picture_on() -> bool:
	var c = weapons.host.get("cockpit")
	return flir_state() == 3 and c != null and c.hud.visible and not c.hud.hud_failed()


func shifted() -> bool:
	return picture_on() and picture_shift_deg().length() > 1.0


func _update_picture() -> void:
	var c = weapons.host.get("cockpit")
	if c == null:
		return
	var on := picture_on()
	if _picture == null:
		if not on:
			return
		_picture = ColorRect.new()
		_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_picture.show_behind_parent = true
		var mat := ShaderMaterial.new()
		mat.shader = load(HUD_FLIR)
		_picture.material = mat
		c.hud.add_child(_picture)
	_picture.visible = on
	if not on:
		return
	_picture.position = Vector2.ZERO
	_picture.size = c.hud.size
	var mat: ShaderMaterial = _picture.material
	var mask = c.get("_hud_mask")
	mat.set_shader_parameter("count", mask.get_shader_parameter("count") if mask != null else 0)
	if mask != null:
		mat.set_shader_parameter("corners", mask.get_shader_parameter("corners"))
	mat.set_shader_parameter("gain", GAINS[gain_i])
	mat.set_shader_parameter("level", level)
	mat.set_shader_parameter("black_hot", black_hot)
	# The shift in screen UV: the view's degrees per screen height (the camera's vertical field of view).
	var cam: Camera3D = c.hud.camera
	var fov := cam.fov if cam != null else 60.0
	var view: Vector2 = c.get_viewport_rect().size
	var d := picture_shift_deg() / fov
	mat.set_shader_parameter("shift", Vector2(d.x * view.y / maxf(view.x, 1.0), -d.y))


## The cockpit's state for the FLIR and TFR formats and the HUD ({} without a pod).
func state() -> Dictionary:
	if kind == 0:
		return {}
	var s := {
		"kind": kind,
		"flir": flir_state(),
		"flir_stby": flir_stby,
		"black_hot": black_hot,
		"gain": GAINS[gain_i],
		"level": level,
		"adv": adv_on(),
		"man_flyup": man_flyup,
		"rf": rf_pos(),
		"hud_tf": hud_tf(),
		"shifted": shifted()
	}
	if tfr():
		s.merge(settings())
		s.merge(out)
		s.profile = _profile
	return s


## The FLIR and TFR formats' OSBs (f16_mfd.gd FLIR_OSBS, TFR_OSBS).
func osb(action: String) -> void:
	match action:
		"stby":
			flir_stby = not flir_stby
		"polarity":
			black_hot = not black_hot
		"gain_up", "gain_down":
			step_gain(action == "gain_up")
		"level_up", "level_down":
			step_level(action == "level_up")
		"mode", "scp", "ride":
			next_setting(["mode", "scp", "ride"].find(action))


func _roll() -> float:
	var f = weapons.host.get("flight")
	return float(f.state().get("roll", 0.0)) if f != null else 0.0
