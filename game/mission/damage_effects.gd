# Explosions, debris and smoke of destroyed / damaged units (docs/damage.md §6). Timing, sizes,
# speeds and counts are the original's (the Tgen explosion object FUN_00416850 and its per-flag
# updates, the class switch FUN_0059b3b0, the damage-smoke emitter FUN_004d1990); the drawing is
# ours: soft procedural billboards in one MultiMesh per material instead of the 1998 sprite strips
# (airexp1 / smoke3), and a short light for the one-frame lens flash.
# Positions are Godot scene coordinates (metres, Y up).
extends Node3D

## Explosion flag bits (FUN_00416850 / FUN_00416a40, docs/damage.md §6.1).
const F_SHATTER := 0x2
const F_SMOKE_TRAILS := 0x8
const F_FIREBALL := 0x10
const F_BURN_PIECES := 0x20
const F_NO_DELAY := 0x40
const F_KICK := 0x80
const F_PUFF := 0x100
const F_WHITE := 0x400
const F_COLUMN := 0x800
const F_REST := 0x1000
const F_FLASH := 0x4000
const F_SMALL_FIRE := 0x10000000

## World size of a sprite: full width = 0.2 · size · texture width (FUN_00410660; UNCERTAIN, see
## docs/damage.md §6.1): AirExp1 (128 px, size 10) and smoke3 (64 px, size 1).
const FIREBALL_WIDTH := 0.2 * 10.0 * 128.0
const SMALL_FIRE_WIDTH := FIREBALL_WIDTH * 0.15
const SMOKE_WIDTH := 0.2 * 1.0 * 64.0
const FIREBALL_TIME := 1.2
const PUFF_TIME := 2.5
## Gravity of pieces and streamers: z -= 15 t² (g = 30 world units / s²).
const PIECE_G := 30.0
## Smoke column (FUN_00416ea0): 33 / (4 - detail) puffs, one every 1.6 s, visible from 0.3 s until
## 36 / (4 - detail) s. The detail setting's default is not traced: the highest (3) is used.
const COLUMN_DETAIL := 3
## Puff emitters (damage smoke, smoking pieces, streamers) spawn one puff per rendered frame in the
## original, so the density follows the frame rate; here a fixed 30 Hz "frame" (our choice).
const PUFF_RATE := 30.0
## Shatter: one piece per model polygon in the original; we fly a fixed number of chunks.
const PIECES := 24

var _rng := RandomNumberGenerator.new()
## Live puffs: {pos, vel, age, life, w0, w1 (width at birth / death), grey, fire, delay}.
var _puffs: Array = []
var _pieces: Array = []  # {node, vel, spin, age, life, rest_y, ground_y, large, delay, smoke_t}
var _streamers: Array = []
var _columns: Array = []  # {pos, age, n, end}
var _smokers := {}  # Node3D -> accumulated time (damage smoke, FUN_004d1990)
var _mm_smoke: MultiMeshInstance3D
var _mm_fire: MultiMeshInstance3D
## Terrain height at a scene position (null when unknown), supplied by the host.
var ground_at: Callable


func _ready() -> void:
	_mm_smoke = _make_layer(false)
	_mm_fire = _make_layer(true)


func _make_layer(fire: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_texture(fire)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if fire:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = mat
	mm.mesh = quad
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


## A soft round sprite (smoke: grey noise-free blob; fire: hot core).
static func _soft_texture(fire: bool) -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			if fire:
				img.set_pixel(x, y, Color(1.0, lerpf(0.35, 0.95, a), lerpf(0.05, 0.6, a * a), a))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, a * 0.85))
	return ImageTexture.create_from_image(img)


# --- the explosion object (FUN_00416850) ---------------------------------------------------------

## What a destroyed unit's explosion looks like (FUN_0059b3b0) by unit class, bdb type code (0x5b4)
## and where it is: `low` = below ground + 10.5 m (0x60db1c), `water` = terrain type 1 / 2 (our
## terrain has no types: never). Returns {flags, scale, duration} ({} = none); the constructor's
## scale 4 and the event duration 95 s unless the class says otherwise. Aircraft low on land also
## place a crater 1 s later (CreateCraterEv; the pool of class-0x1f objects is empty in the shipped
## data). The sound is SFX_AIRCRAFT_EXPLODED for every unit class (code 0x11).
static func explosion_for(klass: int, type_code: int, low: bool, water: bool) -> Dictionary:
	var e := {"flags": 0, "scale": 4.0, "duration": 95.0}
	match klass:
		1, 2, 3, 0x1c:
			e.flags = (0x640ba if water else 0x58ba) if low else 0x407a
		5, 10:
			e.flags = 0x58ba
		6, 8, 9, 0xb:
			e.flags = 0x188a
		0xc, 0xd:
			if type_code == 410:
				e.flags = 0x4810
			elif type_code == 420:
				e.flags = 0x1892
				e.scale = 2.0
			else:
				e.flags = 0x800
		0xf, 0x10:
			e.flags = 0x640ba
			e.scale = 1.5
		_:
			return {}
	return e


## One explosion event at `pos`: `flags` as above, `scale` (param[7]), `duration` (param[6], the
## lifetime of the whole event), `ground_y` = terrain height under it, `radius` = the unit's size
## (the shatter pieces start within it).
func explosion(pos: Vector3, flags: int, scale: float, duration: float, ground_y: float, radius := 6.0) -> void:
	if flags & F_FLASH:
		_flash(pos)
	if flags & F_FIREBALL:
		_add_puff(pos, Vector3.ZERO, FIREBALL_TIME, FIREBALL_WIDTH, FIREBALL_WIDTH, 250, true, 0.0, true)
	if flags & F_SMALL_FIRE:
		_add_puff(pos, Vector3.ZERO, FIREBALL_TIME, SMALL_FIRE_WIDTH, SMALL_FIRE_WIDTH, 250, true, 0.0, true)
	if flags & F_PUFF:
		smoke_puff(pos, flags & F_WHITE != 0)
	if flags & F_SHATTER:
		_shatter(pos, flags, scale, duration, ground_y, radius)
	elif flags & F_SMOKE_TRAILS:
		_streamers_at(pos, scale)
	if flags & F_COLUMN:
		_columns.append({"pos": pos, "age": 0.0, "n": 33 / (4 - COLUMN_DETAIL), "born": 0, "end": duration})


## 0x100: smoke3 puff, 2.5 s, width 1x -> 3x, grey 40 (0x400: white), rising 5.6..10.1 m/s with
## ±2.4 m/s sideways jitter (no wind: the mission weather is not decoded).
func smoke_puff(pos: Vector3, white := false) -> void:
	var v := Vector3((_rng.randi() & 15) - 8, 8.0 + ((_rng.randi() & 15) - 8) * 0.3, (_rng.randi() & 15) - 8)
	v.x *= 0.3
	v.z *= 0.3
	_add_puff(pos, v, PUFF_TIME, SMOKE_WIDTH, SMOKE_WIDTH * 3.0, 255 if white else 40, false, 0.0, true)


func _add_puff(pos: Vector3, vel: Vector3, life: float, w0: float, w1: float, grey: int, fire: bool, delay: float,
		bottom: bool) -> void:
	_puffs.append({"pos": pos, "vel": vel, "age": 0.0, "life": life, "w0": w0, "w1": w1, "grey": grey,
			"fire": fire, "delay": delay, "bottom": bottom})


## 0x4000: the lens flash, drawn for one frame in the original; a 0.1 s light here.
func _flash(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 16.0
	l.omni_range = 600.0
	add_child(l)
	l.position = pos
	var t := create_tween()
	t.tween_property(l, "light_energy", 0.0, 0.1)
	t.tween_callback(l.queue_free)


## 0x2: the model shatters (FUN_00417280 / FUN_004175e0): each piece flies at
## (offset + base) · k · scale, k in {0.5, 1, 1.5}, base = 5 up with 0x80; spin up to ±0.96 rad/s;
## g = 30; life (1 + rand%100·0.01) · duration · 0.5; start delay 0..0.3 s unless 0x40. With 0x1000
## pieces come to rest at the origin altitude - 0.5 and lie there, else they vanish at the ground.
## With 0x8 large flying pieces trail smoke; with 0x20 they may flare into a small fire (1/32 per
## frame) and vanish.
func _shatter(pos: Vector3, flags: int, scale: float, duration: float, ground_y: float, radius: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.14)
	for i in PIECES:
		# A polygon's position in the model: a random point within the unit's size (ours).
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.25, 0.4), _rng.randf_range(-1, 1)) * radius
		var base := Vector3(0, 5.0, 0) if flags & F_KICK else Vector3.ZERO
		var k: float = [0.5, 1.0, 1.5][_rng.randi() % 3]
		var box := BoxMesh.new()
		box.size = Vector3(_rng.randf_range(0.4, 2.0), _rng.randf_range(0.1, 0.5), _rng.randf_range(0.4, 2.0))
		box.material = mat
		var node := MeshInstance3D.new()
		node.mesh = box
		node.position = pos + off
		node.visible = flags & F_NO_DELAY != 0
		add_child(node)
		_pieces.append({
			"node": node, "vel": (off + base) * k * scale,
			"spin": Vector3((_rng.randi() & 63) - 32, (_rng.randi() & 63) - 32, (_rng.randi() & 63) - 32) * 0.03,
			"age": 0.0, "life": (1.0 + (_rng.randi() % 100) * 0.01) * duration * 0.5,
			"delay": 0.0 if flags & F_NO_DELAY else (_rng.randi() % 100) * 0.003,
			"rest_y": pos.y - 0.5 if flags & F_REST else -INF, "ground_y": ground_y,
			"large": i % 3 == 0, "smoke": flags & F_SMOKE_TRAILS != 0, "burn": flags & F_BURN_PIECES != 0,
			"smoke_t": 0.0, "resting": false,
		})


## 0x8 without 0x2 (FUN_004182b0): 12 smoke streamers every 30°, 5·scale sideways and 3·scale up,
## g = 30, each trailing puffs until it drops 1 m below the origin; then a 9 s smoke column.
func _streamers_at(pos: Vector3, scale: float) -> void:
	var s := {"pos": pos, "items": [], "t": 0.0}
	for i in 12:
		var a := deg_to_rad(30.0 * i)
		s.items.append({"p": pos - Vector3(0, 0.5, 0), "v": Vector3(cos(a) * 5.0 * scale, 3.0 * scale, sin(a) * 5.0 * scale), "on": true})
	_streamers.append(s)


# --- damage smoke (FUN_004d1880 / FUN_004d1990) --------------------------------------------------

## Start / stop the damage smoke of a unit: one 0x100 puff per frame at the unit.
func set_smoke(node: Node3D, on: bool) -> void:
	if node == null:
		return
	if on:
		_smokers[node] = 0.0
	else:
		_smokers.erase(node)


func _process(delta: float) -> void:
	var step := 1.0 / PUFF_RATE
	for node in _smokers.keys():
		if not is_instance_valid(node):
			_smokers.erase(node)
			continue
		_smokers[node] += delta
		while _smokers[node] >= step:
			_smokers[node] -= step
			smoke_puff(node.global_position)
	_update_pieces(delta, step)
	_update_streamers(delta, step)
	_update_columns(delta)
	_update_puffs(delta)


func _update_pieces(delta: float, step: float) -> void:
	for i in range(_pieces.size() - 1, -1, -1):
		var p: Dictionary = _pieces[i]
		var node: MeshInstance3D = p.node
		p.age += delta
		if p.age < p.delay:
			continue
		node.visible = true
		if p.age > p.life:
			node.queue_free()
			_pieces.remove_at(i)
			continue
		if p.resting:
			continue
		p.vel.y -= PIECE_G * delta
		node.position += p.vel * delta
		node.rotation += p.spin * delta
		if node.position.y <= p.rest_y:
			node.position.y = p.rest_y
			p.resting = true
			continue
		if node.position.y <= p.ground_y and p.rest_y == -INF:
			node.queue_free()
			_pieces.remove_at(i)
			continue
		if p.large:
			p.smoke_t += delta
			while p.smoke_t >= step:
				p.smoke_t -= step
				if p.smoke:
					smoke_puff(node.position)
				if p.burn and _rng.randi() % 32 == 0:
					_add_puff(node.position, Vector3.ZERO, FIREBALL_TIME, SMALL_FIRE_WIDTH, SMALL_FIRE_WIDTH, 250, true, 0.0, true)
					p.age = p.life + 1.0


func _update_streamers(delta: float, step: float) -> void:
	for i in range(_streamers.size() - 1, -1, -1):
		var s: Dictionary = _streamers[i]
		s.t += delta
		var live := false
		for it in s.items:
			if not it.on:
				continue
			it.v.y -= PIECE_G * delta
			it.p += it.v * delta
			if it.p.y < s.pos.y - 1.0 or s.t > 30.0:
				it.on = false
				continue
			live = true
		while s.t >= step and live:
			s.t -= step
			for it in s.items:
				if it.on:
					smoke_puff(it.p)
		if not live:
			_columns.append({"pos": s.pos, "age": 0.0, "n": 33 / (4 - COLUMN_DETAIL), "born": 0, "end": 9.0})
			_streamers.remove_at(i)


## 0x800 column (FUN_00416fd0): puff i is born at i·1.6 s, rises 2.5..5.8 m/s with ±1.5 m/s
## sideways, is visible from 0.3 s to 36/(4 - detail) s, width 12.8 m · (1 + 0.32·age), grey 10..79.
func _update_columns(delta: float) -> void:
	for i in range(_columns.size() - 1, -1, -1):
		var c: Dictionary = _columns[i]
		c.age += delta
		while c.born < c.n and c.age >= c.born * 1.6 and c.born * 1.6 < c.end:
			var v := Vector3((_rng.randi() % 10 - 5) * 0.3, 4.0 + (_rng.randi() % 12 - 5) * 0.3, (_rng.randi() % 10 - 5) * 0.3)
			var life := minf(36.0 / (4 - COLUMN_DETAIL), c.end - c.born * 1.6)
			_add_puff(c.pos, v, life, SMOKE_WIDTH, SMOKE_WIDTH * (1.0 + 0.32 * life), 10 + _rng.randi() % 70, false, 0.3, true)
			c.born += 1
		if c.born >= c.n or c.age >= c.end:
			_columns.remove_at(i)


func _update_puffs(delta: float) -> void:
	var smoke: Array = []
	var fire: Array = []
	for i in range(_puffs.size() - 1, -1, -1):
		var p: Dictionary = _puffs[i]
		p.age += delta
		if p.age >= p.life:
			_puffs.remove_at(i)
			continue
		p.pos += p.vel * delta
		if p.age < p.delay:
			continue
		(fire if p.fire else smoke).append(p)
	_fill(_mm_smoke.multimesh, smoke)
	_fill(_mm_fire.multimesh, fire)


func _fill(mm: MultiMesh, list: Array) -> void:
	mm.instance_count = list.size()
	for i in list.size():
		var p: Dictionary = list[i]
		var f: float = p.age / p.life
		var w: float = lerpf(p.w0, p.w1, f)
		# Bottom-anchored sprites (the quad rises by its height above the point).
		var at: Vector3 = p.pos + Vector3(0, w * 0.5 if p.bottom else 0.0, 0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(w, w, w)), at))
		var g: float = p.grey / 255.0
		var a := 1.0 - f if p.fire else clampf(1.0 - f * f, 0.0, 1.0)
		mm.set_instance_color(i, Color(g, g, g, a) if not p.fire else Color(1, 1, 1, a))


## Live counts, for tests.
func counts() -> Dictionary:
	return {"puffs": _puffs.size(), "pieces": _pieces.size(), "columns": _columns.size(), "smokers": _smokers.size()}
