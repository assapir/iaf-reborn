# The player's autopilot (docs/autopilot.md): the controller side of the original (FUN_0044a240 cases 1 / 0xa /
# 0x10 / throttle, mode ctl+0x974, lamp 8) and the HUD's waypoint sequencing (FUN_00452960). The control loops
# are the AI's (crates/iaf-flight/src/autopilot.rs, one control law for AI and player), run through IafFlight.
extends RefCounted

## The flight scene (terrain_view.gd): flight, cockpit, route, stick / throttle / lever state.
var host: Node
## ctl+0x974: 0 off, 1 level (HUD "AP LVL"), 2 navigation ("AP NAV"); 1 → 2 → 0 on the A key.
var mode := 0
## The last keyboard stick event (DAT_008338f0 / f4, ±1): the keys rewrite roll / pitch into one GEV 1 (x, y).
var kb_stick := Vector2.ZERO
## FUN_00452960 waypoint box state: +0x48 inside once, +0x40 the closest distance so far.
var nav_inside := false
var nav_min := NAV_MIN_INIT

## The stick / rudder events at or beyond ±51 (of ±100) disengage the autopilot (@44bd0e, case 0xa).
const BREAK_OUT := 0.51
## The waypoint box half size (2 · 1854 · 0.5 m, 0x600de0 / 0x600df8) and the "near" radius of an action-5
## waypoint (0x600df0); the reset of the closest distance (0x600de4).
const NAV_BOX := 1854.0
const NAV_NEAR := 18540.0
const NAV_MIN_INIT := 1112400.0
## Throttle the disengage re-sync posts without a throttle axis (FUN_005a29d0: axis −1 → 0.74 when airborne).
const RESYNC_THROTTLE := 0.74


func _init(h: Node) -> void:
	host = h


## Controller init (@4483d7): an airborne start begins with the autopilot on in level mode, lamp lit.
func start(airborne: bool) -> void:
	_engage(1 if airborne else 0)


## GEV 0x10 (A key, lamp click, the landing's StopPlane; @44d13a): refused while the autopilot is damaged
## (system 6); on the ground the press always goes to off; 0 → 1 (lamp on) → 2 → 0 (lamp off, throttle re-sync).
func key() -> void:
	if host.player_damage.flags[6]:
		return
	var old := mode
	if host.flight.state().on_ground:
		old = 2
	match old:
		0:
			_engage(1)
		1:
			_engage(2)
		2:
			_engage(0)
			_resync_throttle()


## A stick event (GEV 1 from the roll / pitch keys, FUN_004e0b80, or the joystick, FUN_004df560; only the keys'
## is kept as the last keyboard stick): with the autopilot lamp on, an event
## within ±51 is dropped (the autopilot keeps the stick); beyond, the autopilot goes off first. Returns whether
## the stick reaches the flight model.
func stick_event(v: Vector2, from_keys := true) -> bool:
	if from_keys:
		kb_stick = v
	if not host.cockpit.indicators[8]:
		return true
	if absf(v.x) < BREAK_OUT and absf(v.y) < BREAK_OUT:
		return false
	var old := mode
	_engage(0)
	if old != 1:
		_resync_throttle()
	return true


## GEV 10 (rudder keys): always posted; beyond ±51 it also turns the autopilot off (no throttle re-sync).
func rudder_event(r: float) -> void:
	if host.cockpit.indicators[8] and absf(r) >= BREAK_OUT:
		_engage(0)


## Throttle commands (GEV 4 / 9, RPM ± 5 %) are dropped in NAV (the autopilot holds the throttle).
func throttle_allowed() -> bool:
	return mode != 2


## Damage 6 (FUN_0044d760 case 6): lamp off and the loop stopped; ctl+0x974 keeps its value (as coded).
func damaged() -> void:
	if host.cockpit.indicators[8]:
		host.cockpit.indicators[8] = false
		host.flight.ap_player_mode(0, 0)


## One frame before the flight model steps: the loop's tick, its commands mirrored on the levers (they reach
## the jet through the controller, as the original's GEV posts), then the waypoint sequencing.
func update(world: Vector2) -> void:
	var o: Dictionary = host.flight.ap_step(host._sim_time)
	if o.has("stick_x"):
		host.stick = Vector2(o.stick_x, o.stick_y)
	if o.has("throttle"):
		host.throttle = o.throttle
	if o.has("rudder"):
		host.rudder = o.rudder
	if o.has("brakes"):
		host.brakes = o.brakes
	if o.has("gear_down") and o.gear_down != host.gear_down:
		host._toggle_gear()
	if o.has("flaps") and (o.flaps != (host.flaps > 0.0)):
		host._flaps_lever()
	if o.get("ap_key", false):
		key()  # StopPlaneCL in FM mode 0 presses the autopilot key (forced)
	_nav_update(world)


## Selects waypoint i (FUN_004532a0 / FUN_00453370 and the next / previous keys): the box state restarts and
## NAV re-targets the new waypoint.
func set_waypoint(i: int) -> void:
	var n: int = maxi(host.route.size(), 1)
	host.cockpit.current_waypoint = posmod(i, n)
	nav_inside = false
	nav_min = NAV_MIN_INIT
	if mode == 2:
		host.flight.ap_player_mode(2, host.cockpit.current_waypoint)


## FUN_00452960, every controller update: the current waypoint is passed once the jet entered its box
## (|dx| ≤ 1854, dy ≥ −1854: the box has no northern edge, as coded) and its distance then grows; the next
## waypoint is selected unless it was the last. An action-5 waypoint also counts from outside the box beyond
## 18.54 km, and within that only in NAV; the radio reports it 3 s later (docs/radio.md §4).
func _nav_update(p: Vector2) -> void:
	var route: Array = host.route
	var i: int = host.cockpit.current_waypoint
	if i < 0 or i >= route.size():
		return
	var w: Dictionary = route[i]
	var wp: Vector2 = w.world
	var act5: bool = int(w.get("action", 0)) == 5
	var d := wp.distance_to(p)
	var near := act5 and d < NAV_NEAR
	var inside := p.x >= wp.x - NAV_BOX and p.x <= wp.x + NAV_BOX and p.y >= wp.y - NAV_BOX
	if not nav_inside:
		nav_inside = inside
		return
	if not inside and (not act5 or near):
		return
	if d < nav_min:
		nav_min = d
		return
	if near and mode != 2:
		return
	if i + 1 >= route.size():
		return
	set_waypoint(i + 1)
	host.waypoint_passed(i + 1)
	nav_min = (route[i + 1].world as Vector2).distance_to(p)


func _engage(m: int) -> void:
	mode = m
	host.cockpit.indicators[8] = m != 0
	host.flight.ap_player_mode(m, host.cockpit.current_waypoint)


## FUN_005a29d0 (leaving NAV; UNCERTAIN: gated on a vehicle getter == 0x1e): the throttle goes back to the
## throttle axis (FUN_004e0f40 × 0.01), 0.74 without one, only when airborne.
func _resync_throttle() -> void:
	if host.flight.state().on_ground:
		return
	var axis: int = Joystick.throttle_axis()
	host.throttle = axis * 0.01 if axis >= 0 else RESYNC_THROTTLE
	host._throttle_event()
