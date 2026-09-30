# The original damage model's rules (docs/damage.md), independent of the scene: the blast formula,
# the damage-level thresholds, the AI-skill scaling and the player's systems-damage pick. The state
# machine that uses them is in mission_runtime.gd (hit / destroy / explode), the effects in
# terrain_view.gd / damage_effects.gd.
extends RefCounted

## MStatus+0x10 damage fraction thresholds (FUN_004a8da0): >= 1.0 (0x6030dc) -> level 5
## (destroyed / exploded), >= 0.8 (0x63f454) -> level 3 (fatally hit, "going down").
const DESTROY_AT := 1.0
const HIT_AT := 0.8
## A hit counts only when it adds at least 0.01 (0x603108) or destroys (FUN_004a97b0).
const MIN_STEP := 0.01
## AI skill (Preferences > Gameplay, pref +0x50): damage to units not on the player's side is scaled
## by 0.8 (Rookie, 0x63900c) / 0.9 (Normal, 0x639010) / 1.0 (Expert) in FUN_004642f0.
## Original bug: that makes the enemies tougher on the easier levels (the other skill readers 4404d0 /
## 443f60 do weaken them). Preferences > Physics "fix_skill_damage" turns the scaling off (ours).
const SKILL_SCALE := [0.8, 0.9, 1.0]
static var no_skill_scale := false
## Damage smoke of a hit controlled aircraft (class 0x1c, FUN_004a9c60 / FUN_004a7de0): starts at
## damage >= 0.25 (0x6030b0); after 20 s (0x8321a0) it stops unless damage >= 0.5 (0x6030b4).
const SMOKE_AT := 0.25
const SMOKE_KEEP_AT := 0.5
const SMOKE_CHECK := 20.0

## Unit status states (MStatus+0xc).
const ALIVE := 1
const HIT := 3
const DESTROYED := 4
const EXPLODED := 5


## FUN_004642f0: damage of a blast at `point` with `power` and `radius` on a target at `pos` whose
## size is `size` (0 when it has none). Per axis the distance is reduced by the size (clamped at 0);
## outside the radius on any axis there is no damage, else
## |(dx - R)(dy - R)(dz - R)| * power / R^3 (= power at the centre, falling off per axis).
static func blast(pos: Vector3, size: float, point: Vector3, power: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var d := (pos - point).abs()
	for i in 3:
		d[i] = maxf(d[i] - size, 0.0)
		if d[i] > radius:
			return 0.0
	return absf((d.x - radius) * (d.y - radius) * (d.z - radius)) * power / (radius * radius * radius)


## The rest of FUN_004642f0: scale by the AI skill for units not on the player's side, then
## returns [new damage fraction, destroyed]. `strength` = the target's damage object +4.
static func add_damage(damage: float, dmg: float, strength: float, enemy_of_player: bool, ai_level: int) -> Array:
	if enemy_of_player and ai_level >= 0 and ai_level < 2 and not no_skill_scale:
		dmg *= SKILL_SCALE[ai_level]
	if strength <= dmg:
		return [1.0, true]
	if strength != 0.0:
		damage += dmg / strength
	if damage >= DESTROY_AT:
		return [1.0, true]
	return [damage, false]


## FUN_004a8da0: the level a damage fraction asks for (-1 = none, only stored).
static func level_for(damage: float) -> int:
	if damage >= DESTROY_AT:
		return EXPLODED
	if damage >= HIT_AT:
		return HIT
	return -1


# --- the player's systems (player controller damage, FUN_0044d590 -> FUN_0045cd80 -> FUN_0044d760) ----

## Damage codes (FUN_0044d760): the console text (the left / right variant for twin-engine jets) and the
## other flags a code sets. Flag n = damage page row (FUN_0052bc00, cockpit state +0x550 + 4n).
const SYSTEMS := {
	1: {"text": "ECM damage"},
	2: {"text": "Engine cut out - restart throttle", "twin": "Left engine cut out - restart throttle", "also": [8]},
	3: {"text": "Engine cut out - restart throttle", "twin": "Right engine cut out - restart throttle", "also": [9]},
	4: {"text": "Flaps damage"},
	5: {"text": "Air brakes damage"},
	6: {"text": ""},
	7: {"text": "Gear damage"},
	8: {"text": "After burner damage", "twin": "Left After burner damage"},
	9: {"text": "After burner damage", "twin": "Right After burner damage"},
	10: {"text": "Fuel leak - reduce throttle"},
	11: {"text": "Instuments damage"},
	12: {"text": "Hud damage"},
	13: {"text": "Gun damage"},
	14: {"text": "RWR damage"},
	15: {"text": "Radar damage"},
	16: {"text": "Engine on fire - use extinguisher", "twin": "Left engine on fire - use extinguisher", "also": [8]},
	17: {"text": "Engine on fire - use extinguisher", "twin": "Right engine on fire - use extinguisher", "also": [9]},
	18: {"text": "Hydraulic control"},
	19: {"text": "Main generator failure", "also": [15, 14]},
	20: {"text": "Weapon systems damage"},
	21: {"text": "Total generator failure", "also": [15, 20, 14, 1, 11, 12]},
	22: {"text": "Engine permanent damage", "twin": "Left Engine permanent damage", "also": [8]},
	23: {"text": "Engine permanent damage", "twin": "Right Engine permanent damage", "also": [9]},
	24: {"text": "Total flight control"},
}


## FUN_0045cf20: may system `n` be damaged. `twin` = twin-engine jet (controller +8 -> +0x24),
## `player` = the player's own jet, `ecm` = ECM fitted (FUN_004581d0), `cut_out` = +0x70 (an engine
## cut-out was picked), `flags` = the damage flags (index 0..24).
static func system_allowed(n: int, flags: Array, twin: bool, player: bool, ecm: bool, cut_out: bool) -> bool:
	if not twin and n in [9, 3, 0x17, 0x11]:
		return false
	if not player and n in [3, 2, 7, 5]:
		return false
	if n == 1 and not ecm:
		return false
	if cut_out and n == 2:
		return false
	if n == 3:
		return false
	if n != 2:
		return true
	return not (flags[9] or flags[0x17] or flags[0x11])


## FUN_0045cd80: which system a hit that left the jet at `damage` (0 < damage < 1) breaks; 0 = none.
## Returns [code, cut_out]. `rand` returns the CRT rand() (0..32767). Quirk kept: picking 2 or 3 sets
## the cut-out flag before the test, and the test refuses 2 once that flag is set and 3 always, so an
## engine cut-out never happens; the search then steps to a neighbour.
static func pick_system(damage: float, flags: Array, twin: bool, player: bool, ecm: bool, cut_out: bool, rand: Callable) -> Array:
	if damage <= 0.0:
		return [0, cut_out]
	var n := 0
	var tries := 0
	while true:
		if tries > 9:
			break
		if tries + 1 < 9:
			if damage < 0.33:
				n = rand.call() % 6
			elif damage < 0.66:
				n = rand.call() % 9 + 5
			else:
				n = rand.call() % 12 + 13
		else:
			n = rand.call() % 24
		if n == 2 or n == 3:
			cut_out = true
		if n > 0 and n < 25 and (flags[n] or not system_allowed(n, flags, twin, player, ecm, cut_out)):
			var step := 1 if rand.call() % 2 == 1 else -1
			if n < 0x17 and n != 1 and n - 1 >= 0:
				n += step
			while n > 0 and n < 0x17 and n != 1 and n - 1 >= 0 \
					and (not system_allowed(n, flags, twin, player, ecm, cut_out) or flags[n]):
				n += step
		if n >= 0 and n < 25 and flags[n]:
			n = 0
		tries += 1
		if n != 0:
			break
	if n < 0 or n > 24 or not system_allowed(n, flags, twin, player, ecm, cut_out):
		n = 0
	return [n, cut_out]


# --- the destruction motion (motion 0x14, DestructionMotion.cpp; FUN_004a8100 -> FUN_00465c19) ------

## Mover kinds (mover +0x58, FUN_00465f83) by unit class.
static func mover_kind(klass: int) -> int:
	if klass in [5, 6, 8, 9, 10, 11]:
		return 1  # ground vehicles, SAM, AAA, radar
	if klass in [3, 0x1c]:
		return 2  # fixed-wing aircraft (the player too)
	if klass in [1, 2]:
		return 3  # helicopters
	if klass in [0xf, 0x10]:
		return 4  # boats
	if klass >= 0x16 and klass <= 0x1a:
		return 5
	if klass == 7:
		return 6
	return 7  # buildings, trees, sensors …

## Gravity of the fall: 4 g for fixed-wing aircraft (0x63d0e4), none for boats, else 1 g.
const G := 9.806
const FIXED_WING_G := 39.224
## The end check runs every 0.5 s (StopDestructionMotionEvent, 0x8320f0): at 2 m above the ground
## or less (0x602db0) the wreck is snapped to the terrain, explodes and goes to state 5.
const FALL_CHECK := 0.5
const FALL_IMPACT_AGL := 2.0
## FlightModel/pitchEpsilon (5°, 0x8320f8): a falling jet's nose goes to -(90° - ε) at 18°/s.
const PITCH_EPS := 5.0
## Original bug kept: a falling fixed-wing aircraft's heading reads 0 (north) — the heading output is
## only written on the helicopter path (docs/damage.md §3). true = keep its heading (Preferences >
## Physics "fix_fall_heading").
static var fall_keep_heading := false


## FUN_004971ae: start the fall of a unit of `klass` at `pos` (world X, Y, alt), attitude `angles`
## (pitch, roll, heading, degrees), velocity `vel` (world m/s), terrain height `ground`. Returns the
## motion; "timer" = whether the 0.5 s end check runs (fixed-wing aircraft and helicopters only:
## the others stay at state 3 where they are).
static func fall_start(klass: int, pos: Vector3, angles: Vector3, vel: Vector3, ground: float, rand: Callable) -> Dictionary:
	var kind := mover_kind(klass)
	var u := func(): return float(rand.call()) / 32767.0
	var m := {"kind": kind, "p0": pos, "a0": angles, "v0": Vector3.ZERO, "t": 0.0, "T": 0.1,
		"s": (u.call() - 0.5) * 2.0, "timer": false, "n": 0, "yaw_rate": 0.0}
	match kind:
		1, 4, 6:
			# (a, b) = (0.5, 1.0): T = a + (b - a)·U; no motion (the hop velocity is overwritten by 0).
			m.T = 0.5 + 0.5 * u.call()
		2, 3:
			var v := vel
			if kind == 3:
				v.z = clampf(v.z, -10.0, 10.0)
			m.v0 = v
			var h := pos.z + 10.0
			var over_water := ground < 0.1 and kind in [3, 4]
			if h > 0.0 or over_water:
				m.T = 1e8 if kind == 2 else (v.z + sqrt(maxf(v.z * v.z + 19.612 * h, 0.0))) / G
			if m.T <= 0.0:
				m.T = 0.1
			m.timer = true
			m.n = int(3.0 * u.call())
			m.yaw_rate = u.call() * PI
		_:
			m.v0 = vel
	if kind == 2 and angles.x > -85.0 and angles.x < 90.0:
		m.s = -1.0
	return m


## FUN_00497b7c: position (world) and attitude (pitch, roll, heading, degrees) `tau` s into the fall;
## the terrain clamp (z >= terrain where the terrain is above 0.1 m) is the caller's.
static func fall_at(m: Dictionary, tau: float) -> Array:
	var az := -FIXED_WING_G if m.kind == 2 else (0.0 if m.kind == 4 else -G)
	var p: Vector3 = m.p0 + m.v0 * tau + Vector3(0, 0, 0.5 * az * tau * tau)
	var a: Vector3 = m.a0
	var s: float = m.s
	match m.kind:
		2:
			var roll := a.y + rad_to_deg(s * PI * tau)
			# The nose goes to -(90° - ε) at π/10 rad/s; a unit already beyond -85° / 90° with s > 0
			# snaps to -95°.
			var pitch := move_toward(a.x, -(90.0 - PITCH_EPS), 18.0 * tau)
			if not (a.x > -85.0 and a.x < 90.0) and s > 0.0:
				pitch = -95.0
			a = Vector3(pitch, roll, a.z if fall_keep_heading else 0.0)
		3:
			if tau < m.T:
				var th := deg_to_rad(a.x)
				var w: float = (m.n * TAU - s * th) / m.T
				a = Vector3(rad_to_deg(th + s * w * tau), a.y * (1.0 - tau / m.T), a.z + rad_to_deg(s * m.yaw_rate * tau))
			else:
				a = Vector3(a.x, a.y, 0.0)
	return [p, a]


## The damage object's strength (hit points, damage object +4): bdb Objects 0x56e (the type record
## +0x28, spawner FUN_004b7ea3 @4b7ec4), or the class init's 10.0 when it is 0.
static func strength_of(obj: Dictionary) -> float:
	var v := float(obj.get("0x56e", 0))
	return v if v != 0.0 else 10.0


## The unit's size used by the blast formula (entity+8 -> +0x4c): half the spawn radius, which is
## bdb Objects 0x564 (type record +0x30; FUN_004b7634), 5.0 when <= 0 (always for fire sensors,
## class 0x12).
static func size_of(obj: Dictionary) -> float:
	var r := float(obj.get("0x564", 0))
	if int(obj.get("0x5aa", -1)) == 0x12 or r <= 0.0:
		r = 5.0
	return 0.5 * r


## Collision groups / masks (entity+0x18 collider, FUN_0043b1c0) by class: [group, mask]. A unit A
## collides with B when (B.group & A.mask) != 0 and the centres are closer than B's radius
## (FUN_0043c140). Runways and their lights (type 450) are not registered, nor trees, sensors,
## parachutes.
static func collider(klass: int, type_code: int) -> Array:
	if klass in [1, 2, 3, 0x1c]:
		return [2, 0x1b]
	if klass in [5, 6]:
		return [8, 0]
	if klass in [8, 9, 10, 0xb] or (klass in [0xc, 0xd] and type_code != 450):
		return [1, 0]
	if klass in [0xf, 0x10]:
		return [0x10, 0]
	if klass >= 0x16 and klass <= 0x1a:
		return [4, 0x19]
	return []
