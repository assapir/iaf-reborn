# The player's aircraft systems damage (docs/damage.md §5): the player controller's hit reaction
# (FUN_0044d590), the random system pick (FUN_0045cd80 / FUN_0045cf20) and the damage handler
# (FUN_0044d760): console message, damage flags (the MFD damage page rows, FUN_0052bc00), panel
# lights (master caution, engine fire, ECM / AP / RWR off), gear legs stuck, flaps lever refused,
# thumps and Betty calls from the original sound table. Effects on the flight model (engine cut-out,
# afterburner, fuel leak, hydraulics, flight control) are not wired: the flight model has no damage
# inputs yet (docs/damage.md §5.3).
extends RefCounted

const DamageModel := preload("res://mission/damage_model.gd")

## Damage flags 0..24 (controller +0x3d8 + 0xc + 4n; the cockpit state copy +0x550 + 4n).
var flags: Array = []
## +0x70: an engine cut-out was picked (FUN_0045cd80).
var cut_out := false
## +0x96c: the damage at the last shake (FUN_0044d590).
var last_damage := 0.0
## Twin-engine jet (controller +8 -> +0x24; F-15, F-4, F-4 2000, MiG-29): the left / right texts.
var twin := false
## ECM fitted (FUN_004581d0): the F-16's loadout carries no ECM pod by default (UNCERTAIN).
var ecm := false
## Betty voice calls (controller +0x964, FlightSounds.BETTY_TYPES).
var betty := true
var rng := RandomNumberGenerator.new()
## Host callbacks: console(text), sound(code, sub1), light(index, on), gear_stuck(), shake(amount).
var host: Object


func _init() -> void:
	flags.resize(25)
	flags.fill(false)


## CRT rand(): 0..32767.
func _rand() -> int:
	return rng.randi() & 0x7fff


## FUN_0044d590: the jet (still alive) was hit and now has `damage` (0..1). `kind` "gun" = gun rounds
## (bdb type 0x235 of the hitting weapon): the bullets thump, at most every 2 s (controller timer
## +0x840, period 2.0 set @4479e5; FUN_004d4100); else a camera shake (motion 0xd) of 2·(damage increase) (or a random
## 0..1 when the damage did not grow), random sign, clamped to ±1, and the missile-hit thump.
## Then a system may break (single player, 0 < damage < 1).
func hit(damage: float, kind: String, now: float) -> void:
	if kind == "gun":
		if now >= _gun_thump_next:
			_gun_thump_next = now + GUN_THUMP_PERIOD
			host.damage_sound("SFX_AIRCRAFT_DAMAGED", "DAMAGED_GUN_BULLETS")
	else:
		var f: float = float(_rand()) / 32767.0 if damage <= last_damage else damage - last_damage
		if _rand() % 2 == 1:
			f = -f
		host.damage_shake(clampf(f + f, -1.0, 1.0))
		last_damage = damage
		host.damage_sound("SFX_AIRCRAFT_DAMAGED", "DAMAGED_MISSILE_HIT")
	if damage > 0.0 and damage < 1.0:
		var r := DamageModel.pick_system(damage, flags, twin, true, ecm, cut_out, _rand)
		cut_out = r[1]
		if r[0] != 0:
			system_damage(r[0])


var _gun_thump_next := -1.0
const GUN_THUMP_PERIOD := 2.0


## FUN_0044d760: system `n` (1..24) is damaged: its console text, its extra flags and effects, then
## the flag itself, the master caution light and Betty "Caution" (SFX_WARNING WRN_MASTER without Betty).
func system_damage(n: int) -> void:
	var s: Dictionary = DamageModel.SYSTEMS.get(n, {})
	if s.is_empty():
		return
	var text: String = s.get("twin", s.text) if twin else s.text
	if text != "":
		host.damage_console(text)
	for f in s.get("also", []):
		flags[f] = true
	match n:
		1:
			host.damage_light(6, false)  # ECM light off, ECM off (+0x188 = 1, +0x1b8 = 0)
		6:
			host.damage_light(8, false)  # autopilot off (FM motion 0xf)
		7:
			host.damage_gear()  # all three legs 1 (red) for good
		14:
			host.damage_light(3, false)  # RWR off: AI / SAM lights
			host.damage_light(4, false)
		16, 17:
			host.damage_light(1 if n == 16 else 2, true)  # engine fire light, stays on
			if betty:
				host.damage_sound("VOC_BBETTY", "BTY_FIRE")
		19, 21:
			host.damage_sound("SFX_AIRCRAFT_DAMAGED", "DAMAGED_ELECTRICITY")
			if n == 21:
				host.damage_light(6, false)
		2, 3, 22, 23:
			if betty:
				host.damage_sound("VOC_BBETTY", "BTY_ENGINE")
	flags[n] = true
	host.damage_light(0, true)  # master caution (FUN_0045b4b0)
	if betty:
		host.damage_sound("VOC_BBETTY", "BTY_CAUTION")
	else:
		host.damage_sound("SFX_WARNING", "WRN_MASTER")
