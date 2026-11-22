## Modern IAF's air-defence sites (docs/ai.md §15): an S-300PMU-2 battery, a Tor-M1 and a ZSU-23-4, each run by the
## Rust site (IafSite, crates/iaf-ai/src/site.rs). A dev / test hook: no mission places one yet. Each part is a mission
## entity ("ad:N") with a stand-in shape of ours, and each firing part a combat.gd unit without a brain, so the
## launches go through combat.gd's release (the existing missile and gun-round models, the AIM-120's and the 20 mm's
## records standing in) and the locks through its on_lock (the RWR, an AI jet's brain). Sites may join a network
## (IafNet, crates/iaf-ai/src/net.rs, docs/ai.md §15.5): its search radar cues their track radars.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const BaseFurniture := preload("res://shared/terrain/base_furniture.gd")
const Missile := preload("res://shared/weapons/missile.gd")

## The decision tick (s): the site tests line of sight only then (docs/ai.md §15.3).
const TICK := 0.5
## The stand-in records: the existing models as they are (the sites' own records are drafts, threat-records.md).
const SAM_RECORD := "AIM-120"
const GUN_RECORD := "20 MM"
## Every part's strength and spawn radius (threat-records.md §3: the vehicles held at 300).
const STRENGTH := 300.0
const RADIUS := 8.0
## The stand-ins' array faces and missile canisters.
const FACE := Color(0.2, 0.22, 0.2)
const CANISTER := Color(0.42, 0.45, 0.31)

var host: Node  # terrain_view.gd
var cb: Node  # combat.gd
## Each site: {site (IafSite), parts (its part records), ents (their entities), units (each firing part's combat.gd
## unit, null for a radar), track (the part whose radar locks), locked {target key: true}, flying [[missile, target
## key]], gun {part, key, left, next, err (the laying error)}: the burst firing, cued {target key: true}: the
## network's cues (EMCON cue), next (the next tick)}.
var sites: Array = []
## Each network: {net (IafNet), gci (IafGci: its vector for the enemy fighters, ai_flights.gd enemy_flight), ents [the
## 64N6E2, the 54K6E2], sites (its members' site records), next (the next tick)}.
var nets: Array = []
var _n := 0


## The sites of the flight `h` (terrain_view.gd), made on first use.
static func of(h: Node) -> Node:
	var n: Node = h.ai.get_node_or_null("AirDefence")
	if n == null:
		n = load("res://shared/ai/air_defence.gd").new()
		n.name = "AirDefence"
		n.host = h
		n.cb = h.ai.combat
		h.ai.add_child(n)
	return n


## A site of `kind` (s300, tor, zsu) centred at `pos` (world), facing `heading` (degrees), with its alternate positions
## (world); its parts' entities, [] for an unknown kind. `side` −1: the player's enemy.
func spawn(kind: String, pos: Vector3, heading := 0.0, alternates := [], side := -1) -> Array:
	var site = IafSite.create(kind, pos, heading, alternates)
	if site == null:
		return []
	site.set_skill(Settings.enemy_skill())  # the crew's: the pilot's pick (docs/ai.md §17)
	var rt: Node = host.runtime
	side = _side(side)
	var s := {
		"site": site,
		"parts": site.parts(),
		"ents": [],
		"units": [],
		"track": 0,
		"locked": {},
		"flying": [],
		"gun": {},
		"cued": {},
		"next": float(rt.now)
	}
	var at: Array = site.positions(host.mission_ground)
	var record := _record(GUN_RECORD if kind == "zsu" else SAM_RECORD)
	for i in s.parts.size():
		var p: Dictionary = s.parts[i]
		var ent := _part(p, at[i], heading, side)
		s.units.append(cb.add_ground_unit(ent, record) if int(p.rounds) > 0 and not record.is_empty() else null)
		s.ents.append(ent)
	s.track = maxi(0, s.parts.map(func(p): return p.track).find(true))
	sites.append(s)
	return s.ents


## An 83M6E2 network over the site records `members` (site_of): its 64N6E2 search radar at `radar_pos` and its 54K6E2
## command post at `post_pos` (world, on the ground), facing `heading`. Its two entities; while both stand, the sites
## run on its cues with their own search radars off; losing either leaves them autonomous (their own EMCON).
func spawn_net(radar_pos: Vector3, post_pos: Vector3, members: Array, heading := 0.0, side := -1) -> Array:
	var on_ground := func(v: Vector3):
		var g = host.mission_ground(v)
		return Vector3(v.x, v.y, float(g) if g != null else v.z)
	var at := [on_ground.call(radar_pos), on_ground.call(post_pos)]
	var parts: Array = IafNet.parts()
	side = _side(side)
	var ents := []
	for i in parts.size():
		ents.append(_part(parts[i], at[i], heading, side))
	var n := {"net": IafNet.create(at[0]), "gci": IafGci.create(at[0]), "ents": ents, "sites": members}
	n["next"] = float(host.runtime.now)
	nets.append(n)
	return ents


## The network whose 64N6E2 or 54K6E2 is `ent`, {} none (an enemy flight's ground control).
func net_of(ent: Dictionary) -> Dictionary:
	for n in nets:
		if n.ents.any(func(e): return is_same(e, ent)):
			return n
	return {}


## The side −1 stands for: the player's enemy.
func _side(side: int) -> int:
	if side >= 0:
		return side
	return 1 if int(host.runtime.player_entity().get("side", 2)) == 2 else 2


## Part `p` ({name, klass, type_code, reach_km}) as a mission entity ("ad:N") at `at` (world) with its stand-in shape.
func _part(p: Dictionary, at: Vector3, heading: float, side: int) -> Dictionary:
	var rt: Node = host.runtime
	_n += 1
	var e := {"0x1e": -_n, "0x2bc": p.name, "0x2e4": at.x, "0x2ee": at.y, "0x2f8": at.z}
	e.merge({"0x2d0": side, "0x302": heading})
	var ent := MissionRuntime.entity(e, "ad:%d" % _n, -1, false)
	var obj := {"0x5aa": p.klass, "0x5b4": p.type_code, "0x56e": STRENGTH, "0x564": RADIUS, "0x58c": 1}
	if float(p.reach_km) > 0.0:
		obj.radar_km = p.reach_km  # the RWR hears the radar to its reach (player_weapons.gd _rwr_search)
	MissionRuntime._init_damage(ent, obj)
	ent.node = _shape(String(p.name))
	host.add_child(ent.node)
	rt.entities[ent.key] = ent
	host.mission_entity_moved(ent)
	ent.node.rotation.y = -deg_to_rad(heading)
	return ent


## The site record a part of it belongs to, {} for none.
func site_of(ent: Dictionary) -> Dictionary:
	for s in sites:
		if s.ents.has(ent):
			return s
	return {}


func _record(name: String) -> Dictionary:
	for w in cb._db.weapons.values():
		if w.name == name:
			return w
	return {}


## A child of ai_flights.gd: it runs after every jet's step of the frame, so it reads them all at one instant (as
## `_step_flight_ai`), on the runtime's clock.
func _process(_delta: float) -> void:
	if host.frozen or host.waiting_for_ground or host.weapons == null:
		return
	var now: float = host.runtime.now
	for n in nets:
		if now >= n.next:
			n.next = now + TICK
			_net_tick(n, now)
	for s in sites:
		_fire_gun(s, now)
		if now >= s.next:
			s.next = now + TICK
			_tick(s, now)


## The network's decision: its sites' cues (their `cued`, read at their next tick). Its radar radiates while it
## stands; the post emits nothing the RWR hears.
func _net_tick(n: Dictionary, now: float) -> void:
	var up: Array = n.ents.map(func(e): return int(e.state) < 3)
	var members: Array = n.sites.map(
		func(s): return [s.site, s.ents.map(func(e): return int(e.state) < 3), _targets(s)]
	)
	var cues: Array = n.net.tick(now, up[0], up[1], members, host.mission_ground)
	n.gci.tick(now, up[0] and up[1], jets(n.ents[0].side), host.mission_ground)
	for i in n.sites.size():
		n.sites[i].cued = {}
		for key in cues[i]:
			n.sites[i].cued[key] = true
	n.ents[0].radiating = up[0]
	n.ents[1].radiating = false


## One decision: the parts move, radiate and lock as the site says; its launches and bursts go out.
func _tick(s: Dictionary, now: float) -> void:
	s.flying = s.flying.filter(func(f): return f[0] in host.weapons.missiles)
	# A part hit fatally stays at state 3 (damage.md §3): out of action, as combat.gd takes it.
	var alive: Array = s.ents.map(func(e): return int(e.state) < 3)
	var out: Dictionary = s.site.tick(now, alive, _targets(s), host.mission_ground)
	for i in s.ents.size():
		var e: Dictionary = s.ents[i]
		# The RWR's search list takes a radar only while it radiates (player_weapons.gd _rwr_search).
		e.radiating = (s.parts[i].search and out.search) or (s.parts[i].track and out.track)
		var p: Vector3 = out.parts[i]
		e.vel = Vector3.ZERO
		if alive[i] and Vector2(p.x, p.y).distance_to(Vector2(e.world.x, e.world.y)) > 0.01:
			e.vel = (p - e.world) / TICK
			e.world = p
			e.heading = out.heading
			host.mission_entity_moved(e)
			e.node.rotation.y = -deg_to_rad(float(out.heading))
	# Each track a lock from the track radar.
	var radar: Dictionary = s.ents[s.track]
	for key in s.locked.keys():
		if not key in out.tracks:
			_lock(s, radar, key, false)
	for key in out.tracks:
		if not s.locked.has(key):
			_lock(s, radar, key, true)
	for l in out.launches:
		_launch(s, int(l[0]), String(l[1]))
	for b in out.bursts:
		s.gun = {"part": int(b[0]), "key": String(b[1]), "left": int(b[2]), "next": now, "err": b[3]}


func _lock(s: Dictionary, radar: Dictionary, key: String, on: bool) -> void:
	if on:
		s.locked[key] = true
	else:
		s.locked.erase(key)
	cb.on_lock(radar, host.runtime.entities.get(key, {}), on)


## A missile from launcher `part` at `key` through combat.gd's release; a launch it could not make (no sight from the
## launcher, the target gone) gives its round back.
func _launch(s: Dictionary, part: int, key: String) -> void:
	var rt: Node = host.runtime
	var u = s.units[part]
	var t: Dictionary = rt.entities.get(key, {})
	if u == null or t.is_empty() or int(u.ent.state) >= 3:
		s.site.refund(part, key)
		return
	# The launcher turns to the target: the release's attitude is the launcher's heading pitched at it (the part
	# angle +θ to the left of the hull).
	var d: Vector3 = rt._world_of(t) - rt._world_of(u.ent)
	if not u.ent.has("parts"):
		u.ent.parts = {}
	u.ent.parts["launcher"] = wrapf(float(u.ent.heading) - rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)
	# The site counts its own missiles in the air (IafSite), not combat.gd's one per unit.
	u.missile = null
	cb._release(u, t, rt._world_of(t), rt.now, false)
	if u.missile == null:
		s.site.refund(part, key)
	else:
		s.flying.append([u.missile, key])


## The burst's rounds, one per combat.gd GUN_PERIOD, through the fire tick's aim (off by the crew's laying error) and
## release.
func _fire_gun(s: Dictionary, now: float) -> void:
	var g: Dictionary = s.gun
	var u = s.units[g.part] if not g.is_empty() else null
	while u != null and int(u.ent.state) < 3 and g.left > 0 and now >= g.next:
		g.next += cb.GUN_PERIOD
		g.left -= 1
		cb.fire_at(u, host.runtime.entities.get(g.key, {}), now, false, g.err)


## The jets hostile to `side`, alive: the player and the AI aircraft, each with what a radar sees of it (its
## definition's rcs, the bays, the external stores): {id, pos, vel, nose, rcs, bays, stores, ent}.
func jets(side: int) -> Array:
	var rt: Node = host.runtime
	var w: Node = host.weapons
	var out := []
	for e in rt.entities.values():
		if e.side == side or int(e.state) >= 4 or not (e.player or (e.klass in cb.AIR and e.node != null)):
			continue
		var vel: Vector3 = cb._velocity_of(e)
		var stores = w.stores if e.player else cb.units.get(e.key, {}).get("stores")
		(
			out
			. append(
				{
					"id": String(e.key),
					"pos": rt._world_of(e),
					"vel": vel,
					"nose": vel.normalized() if vel.length() > 1.0 else Vector3(0, 1, 0),
					"rcs": Settings.airframe(w.jet_type if e.player else int(e.type_code)).get("rcs"),
					"bays": e.player and w.bay_open(),
					"stores": stores.external() if stores != null else 0,
					"ent": e,
				}
			)
		)
	return out


## The jets hostile to the site (`jets`), each with the network's cue, the launch envelope from the site's first
## launcher and the site's missiles flying at it.
func _targets(s: Dictionary) -> Array:
	var w: Node = host.weapons
	var shooters: Array = s.units.filter(func(x): return x != null)
	var u = shooters[0] if not shooters.is_empty() else null
	var from: Vector3 = host.runtime._world_of(u.ent if u != null else s.ents[0])
	var out := jets(s.ents[0].side)
	for t in out:
		var dlz := Vector2.ZERO
		if u != null and u.rounds != null:
			dlz = Vector2(u.range_m, 0.0)
		elif u != null:
			var own := {"pos": from, "fwd": (t.pos - from).normalized(), "vel": Vector3.ZERO}
			var env: Array = Missile.dlz(w._motion(u.w), own, {"pos": t.pos, "vel": t.vel})
			dlz = Vector2(env[0], env[1])
		t["cued"] = s.cued.has(t.id)
		t["dlz"] = dlz
		t["in_air"] = s.flying.filter(func(f): return f[1] == t.id).size()
	return out


## The stand-in shapes (ours, until a model is approved; docs/ai.md §15.4): boxes in vertex colours, as the bases'
## furniture (base_furniture.gd), the front along −Z; the array faces and dishes as tilted plates.
func _shape(part: String) -> Node3D:
	var olive := BaseFurniture.OLIVE
	var dark := BaseFurniture.SHADOW
	var steel := BaseFurniture.STEEL
	var boxes := []  # [centre, size, colour]
	var plates := []  # [centre, size, colour, tilt back (degrees)]
	match part:
		"96L6E RADAR", "30N6E2 RADAR", "64N6E2 RADAR", "54K6E2":
			# A MAZ-7910 8×8 with its cabins, the antenna on a post (the command post: the cabins only).
			boxes = [
				[Vector3(0, 0.9, 0), Vector3(3, 1.2, 12), olive],
				[Vector3(0, 2.3, -4.8), Vector3(3, 1.6, 2.4), olive],
				[Vector3(0, 2.5, -6.02), Vector3(2.6, 0.7, 0.05), BaseFurniture.GLASS],
				[Vector3(0, 2.6, 1.5), Vector3(3, 2.2, 6), olive],
				[Vector3(0, 4.6, 2.5), Vector3(0.5, 2, 0.5), steel],
			]
			var big := not part.begins_with("30N6E2")
			if part.ends_with("RADAR"):
				plates = [[Vector3(0, 7.2, 2.5), Vector3(6, 3.5, 0.3) if big else Vector3(4.5, 4.5, 0.4), FACE, 20.0]]
			else:
				boxes.pop_back()
		"5P85TE2":
			# A KrAZ tractor and the semi-trailer, its four canisters raised upright.
			boxes = [
				[Vector3(0, 1.6, -6.5), Vector3(2.8, 2.4, 3.5), olive],
				[Vector3(0, 1.3, 1.0), Vector3(2.8, 0.6, 12), olive],
				[Vector3(0, 0.6, 1.0), Vector3(2.6, 0.6, 11), dark],
			]
			for x in [-0.65, 0.65]:
				for z in [6.0, 7.2]:
					boxes.append([Vector3(x, 6.1, z), Vector3(1.1, 9, 1.1), CANISTER])
		"9A331 TOR RADAR":
			# The tracked hull, the turret with its eight rounds between the radars (enemies.md §2.5).
			boxes = [
				[Vector3(0, 1.2, 0), Vector3(3.3, 1.4, 7.5), olive],
				[Vector3(-1.5, 0.6, 0), Vector3(0.5, 1.0, 7.3), dark],
				[Vector3(1.5, 0.6, 0), Vector3(0.5, 1.0, 7.3), dark],
				[Vector3(0, 2.6, 0.5), Vector3(2.6, 1.4, 3.2), olive],
				[Vector3(0, 3.35, 0.8), Vector3(1.6, 0.1, 1.6), steel],
				[Vector3(0, 4.0, 1.6), Vector3(0.2, 1.0, 0.2), steel],
			]
			plates = [
				[Vector3(0, 3.0, -1.25), Vector3(2.0, 1.6, 0.25), FACE, 20.0],
				[Vector3(0, 4.7, 1.6), Vector3(2.4, 0.9, 0.15), FACE, 15.0],
			]
		"ZSU-23-4":
			# The hull, the turret with four barrels and the Gun Dish behind them.
			boxes = [
				[Vector3(0, 1.0, 0), Vector3(3.1, 1.2, 6.5), olive],
				[Vector3(-1.4, 0.5, 0), Vector3(0.5, 0.9, 6.3), dark],
				[Vector3(1.4, 0.5, 0), Vector3(0.5, 0.9, 6.3), dark],
				[Vector3(0, 2.05, 0.2), Vector3(2.6, 0.9, 3.0), olive],
				[Vector3(0, 2.9, 1.5), Vector3(0.15, 0.8, 0.15), steel],
			]
			for x in [-0.35, 0.35]:
				for y in [2.2, 2.5]:
					plates.append([Vector3(x, y + 0.2, -2.6), Vector3(0.12, 0.12, 2.8), steel, 8.0])
			plates.append([Vector3(0, 3.4, 1.5), Vector3(1.4, 1.0, 0.15), FACE, 10.0])
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		BaseFurniture._box(st, b[0], b[1], b[2])
	if (part.ends_with("RADAR") and not part.begins_with("9A331")) or part == "54K6E2":
		BaseFurniture._wheels(st, 3.0, 11.0)
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	body.material_override = BaseFurniture._material()
	root.add_child(body)
	for p in plates:
		var ps := SurfaceTool.new()
		ps.begin(Mesh.PRIMITIVE_TRIANGLES)
		BaseFurniture._box(ps, Vector3.ZERO, p[1], p[2])
		var m := MeshInstance3D.new()
		m.mesh = ps.commit()
		m.material_override = body.material_override
		m.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(p[3])), p[0])
		root.add_child(m)
	return root
