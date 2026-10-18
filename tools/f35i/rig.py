# Rig the andertan "Lockheed Martin F35 Lightning II" model (Sketchfab, CC BY 4.0) for the game (docs/adding-a-plane.md
# §2, docs/f35i.md) with tools/plane/kit.py: real size, the game's frame, the moving parts cut out and named from
# PART_NAMES with their hinge helpers, the nozzle / gun / station / eye / wheel-height points, the IAF skin (our own
# textures: the download's were photographs), blended canopy glass, a decimated nozzle interior. Writes a glTF.
#
#   blender -b --python tools/f35i/rig.py -- <sketchfab scene.gltf> <out dir>
#
# Everything here is F-35I data: which download meshes make which part, the hinge lines, the marking positions.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

SRC, OUT = sys.argv[sys.argv.index("--") + 1:][:2]
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
LENGTH = 15.67  # m (Lockheed Martin)
ORIGIN = Vector((0.0, -1.0, 1.85))  # the aircraft origin (≈ centre of gravity): the game's rig position
EYE = Vector((0.0, 4.1, 3.0))  # in the seat, at seated head height under the canopy (the helmet clears the rim)
SKIN_GREY = (0.37, 0.39, 0.41)  # F-35 low-observable grey, matte (sRGB, before the baked shading)
DOOR_GREY = (0.27, 0.285, 0.30)  # the shut nose doors: the belly's grey after its baked shading
TAIL_NUMBER = "937"  # 116 Sqn "Lions of the South" (F-35I tails run 901-9xx)
# Low-visibility markings as on the IAF's F-35Is (photos, docs/f35i.md §5).
STAR_GREY, DISC_GREY, NUMBER_GREY = (0.17, 0.18, 0.19), (0.46, 0.48, 0.50), (0.16, 0.17, 0.18)


def skin(m):
    metal = kit.material("nozzle_metal", (0.10, 0.10, 0.11), metallic=0.85, roughness=0.35)
    for k in ("50", "51", "52", "53"):
        m[k].data.materials.clear()
        m[k].data.materials.append(metal)
    sizes = {**{m[k]: 2048 for k in ("38", "40", "42", "37", "43", "45")},
             **{m[k]: 1024 for k in ("29", "30", "41", "48", "49", "36")}}
    kit.bake_skin(sizes, SKIN_GREY, no_ao=(m["48"], m["49"]))  # the thin fins: AO rays hit the opposite face


def markings():
    rnd = kit.material("iaf_roundel", (1, 1, 1), metallic=0.15, roughness=0.75,
                       image=kit.image("iaf_roundel", kit.roundel(STAR_GREY, DISC_GREY)), clip=True)
    badge = kit.material("sqn116", (1, 1, 1), metallic=0.15, roughness=0.75,
                         image=kit.image("sqn116_lowvis", kit.low_vis(os.path.join(ASSETS, "sqn116.png"))), clip=True)
    number = kit.material("tail_number", NUMBER_GREY, metallic=0.15, roughness=0.75)
    # One roundel on each upper wing, outboard near the tip and ahead of the flaperon (the USAF tanker-boom photo
    # of an F-35I from above, 2 Aug 2020); one under the right wing.
    for s in (1, -1):
        kit.decal(f"roundel_wing_upper_{'right' if s > 0 else 'left'}", rnd, (4.0 * s, -2.8, 10), (0, 0, -1), 0.8,
                  0.8, (0, 1, 0))
    kit.decal("roundel_wing_lower_right", rnd, (3.6, -2.7, -10), (0, 0, 1), 0.8, 0.8, (0, -1, 0))
    for s in (1, -1):
        # The big roundel on the intake flank behind the lip, the full number on the nose, the last two digits at
        # the fin tip, the badge on the fin (outer faces, forward of the rudder hinge).
        kit.decal(f"roundel_side_{s}", rnd, (8 * s, 2.3, 1.95), (-s, 0, 0), 0.8, 0.8, (0, s, 0))
        kit.text_decal(f"nose_number_{s}", TAIL_NUMBER, number, (8 * s, 5.55, 2.3), (-s, 0, 0), 0.3, (0, s, 0))
        kit.text_decal(f"fin_number_{s}", TAIL_NUMBER[-2:], number, (8 * s, -6.0, 4.15), (-s, 0, 0), 0.26, (0, s, 0))
        kit.decal(f"badge_{s}", badge, (8 * s, -5.5, 3.4), (-s, 0, 0), 0.7, 0.7, (0, s, 0))


def cut_surfaces(m):
    skins = [m[k] for k in ("38", "40", "42", "29", "30", "41")]
    # Flaperons: aft of the y = -3.73 panel line, from the wing root (x 2.2) to x 4.38, ahead of the trailing edge.
    wing = lambda c: abs(c.x) > 2.0 and c.y < -3.0 and 1.9 < c.z < 2.45
    kit.bisect(skins, wing, (0, -3.73, 0), (0, 1, 0))
    for s in (1, -1):
        kit.bisect(skins, wing, (4.38 * s, 0, 0), (1, 0, 0))
    flap = lambda s: (lambda c: 2.2 < c.x * s < 4.38 and -4.6 < c.y < -3.73 and 1.9 < c.z < 2.45)
    parts = {"AilerR": kit.extract(skins, flap(1), "AilerR"), "AilerL": kit.extract(skins, flap(-1), "AilerL")}
    # Stabilators (all-moving): outboard of x 1.02, aft of the swept leading edge (root (1.73, -5.0), tip (3.66, -6.3)).
    stab_zone = lambda c: abs(c.x) > 0.9 and c.y < -4.5 and 2.1 < c.z < 2.45
    le_no = Vector((1.3, 1.93, 0)).normalized()  # the leading edge's horizontal normal, forward
    for s in (1, -1):
        kit.bisect(skins, stab_zone, (1.02 * s, 0, 0), (1, 0, 0))
        kit.bisect(skins, stab_zone, (1.73 * s, -5.0, 0), (le_no.x * s, le_no.y, 0))
    kit.bisect(skins, stab_zone, (0, -5.0, 0), (0, 1, 0))  # inboard of x 1.73 the edge kinks back
    aft_of_le = lambda c, s: (Vector((c.x * s, c.y, 0)) - Vector((1.73, -5.0, 0))).dot(le_no) < 1e-4
    stab = lambda s: (lambda c: c.x * s > 1.02 and c.y < -5.0 and 2.1 < c.z < 2.45 and aft_of_le(c, s))
    parts.update({"ElevaR": kit.extract(skins, stab(1), "ElevaR"), "ElevaL": kit.extract(skins, stab(-1), "ElevaL")})
    # Rudders: aft of the fins' hinge line (root (1.52, -5.55, 2.4) to tip (2.29, -6.8, 4.46)).
    fins = [m["48"], m["49"]]
    rudders = {}
    for s, name in ((1, "Rudde"), (-1, "RuddeL")):
        a, b = Vector((1.52 * s, -5.55, 2.40)), Vector((2.29 * s, -6.80, 4.46))
        le, te = Vector((1.50 * s, -3.81, 2.34)), Vector((1.52 * s, -6.07, 2.40))
        n = (b - a).cross(te - le).normalized()  # ~ the fin's normal
        cut = (b - a).cross(n).normalized()
        if cut.dot(Vector((0, -1, 0))) < 0:
            cut = -cut  # aft
        kit.bisect(fins, lambda c, s=s: c.x * s > 0 and c.z > 2.3, a, cut)
        parts[name] = kit.extract(fins, lambda c, s=s, a=a, cut=cut: c.x * s > 0 and c.z > 2.3 and (c - a).dot(cut) > 1e-4, name)
        rudders[name] = (a, b)
    return parts, rudders


# The weapon bays (between the keel and the intake chines, behind the nose gear): fore / aft ends, and per side the
# keel hinge, the doors' split and the outboard hinge (|x|); the inboard door hangs from the keel, the outboard one
# from the chine.
BAY_Y = (-1.4, 2.9)
BAY_X = (0.35, 0.85, 1.35)
BAY_DEPTH = 0.45


def cut_bays(m):
    belly = [m["42"]]
    zone = lambda c: 0.25 < abs(c.x) < 1.5 and BAY_Y[0] - 0.2 < c.y < BAY_Y[1] + 0.2 and c.z < 1.6
    for y in BAY_Y:
        kit.bisect(belly, zone, (0, y, 0), (0, 1, 0))
    for s in (1, -1):
        for x in BAY_X:
            kit.bisect(belly, zone, (x * s, 0, 0), (1, 0, 0))
    inside = kit.material("bay_inside", (0.30, 0.31, 0.32), roughness=0.8)
    parts, hinges = {}, {}
    for s, side in ((1, "R"), (-1, "L")):
        doors = []
        for k, x0, x1, hx in (("i", BAY_X[0], BAY_X[1], BAY_X[0]), ("o", BAY_X[1], BAY_X[2], BAY_X[2])):
            door = kit.extract(belly, lambda c, s=s, x0=x0, x1=x1: x0 < c.x * s < x1 and BAY_Y[0] < c.y < BAY_Y[1]
                               and c.z < 1.6, f"Bay{side}{k}")
            parts[door.name] = door
            # The hinge on the door's hinged edge, at the belly's height there.
            z = min((v.co.z for v in door.data.vertices if abs(abs(v.co.x) - hx) < 1e-3), default=1.2)
            hinges[door.name] = ((hx * s, BAY_Y[0], z), (0, 1 if (k == "i") == (s > 0) else -1, 0))
            doors.append(door)
        kit.cavity(f"bay_{side}", doors, BAY_DEPTH, inside)
    return parts, hinges


# The external stations (docs/f35i.md §3): letter -> (real F-35A station, span |x| (U: measured off photos and the
# 3-view), pylon depth). A / I are stations 1 / 11 (outboard, AIM-9X), B / H stations 3 / 9 (inboard, heavy).
# Stations 2 / 10 (|x| 3.55) have no game letter. The pylons are our own boxes under the wing, shown in the game
# only while their station carries a store.
PYLONS = {"A": (1, -4.25, 0.22), "B": (3, -2.85, 0.35), "H": (9, 2.85, 0.35), "I": (11, 4.25, 0.22)}


def wing_under(x, y):
    """The wing's lower surface above (x, y) (z), or None."""
    dg = kit.bpy.context.evaluated_depsgraph_get()
    ok, loc, *_ = kit.scene().ray_cast(dg, Vector((x, y, 0.5)), Vector((0, 0, 1)))
    return loc.z if ok and 1.6 < loc.z < 2.6 else None


def pylons():
    """{letter: pylon object} and {letter: station point}: each pylon centred on the wing's local chord, its station
    point (where the store's Pilon helper hangs) at the pylon's foot."""
    mat = kit.material("pylon", SKIN_GREY, metallic=0.15, roughness=0.75)
    objs, points = {}, {}
    for letter, (_, x, depth) in PYLONS.items():
        ys = []  # the chord: the first run of hits from the nose aft (the stabilator lies behind a gap)
        for y in (k / 50 for k in range(150, -300, -1)):
            if wing_under(x, y) is not None:
                ys.append(y)
            elif ys:
                break
        le, te = ys[0], ys[-1]
        length = min(0.6 * (le - te), 2.0)
        yc = (le + te) / 2
        objs[letter], foot = pylon_mesh(f"Pylon{letter}", x, yc, length, depth, mat)
        points[letter] = (x, yc, foot)
    return objs, points


def pylon_mesh(name, x, yc, length, depth, mat, n=16, w_top=0.055, w_foot=0.04):
    """A pylon under the wing at span x: slices along its chord, each slice's top 4 mm under the wing's lower
    surface there (so nothing reaches into or through the wing), a flat foot `depth` below the lowest top, the
    first and last slices short (sloped ends). Returns the object and the foot's height."""
    ys = [yc + length / 2 - length * i / n for i in range(n + 1)]
    tops = [wing_under(x, y) for y in ys]
    known = [t for t in tops if t is not None]
    tops = [(t if t is not None else min(known)) - 0.004 for t in tops]
    foot = min(tops) - depth
    vs, faces = [], []
    for i, (y, top) in enumerate(zip(ys, tops)):
        bot = top - 0.06 if i in (0, n) else foot
        vs += [(x - w_top, y, top), (x + w_top, y, top), (x + w_foot, y, bot), (x - w_foot, y, bot)]
    for i in range(n):
        a, b = 4 * i, 4 * (i + 1)
        faces += [(a, a + 1, b + 1, b), (a + 1, a + 2, b + 2, b + 1), (a + 2, a + 3, b + 3, b + 2), (a + 3, a, b, b + 3)]
    faces += [(0, 3, 2, 1), (4 * n, 4 * n + 1, 4 * n + 2, 4 * n + 3)]
    me = kit.bpy.data.meshes.new(name)
    me.from_pydata(vs, [], faces)
    bm = kit.bmesh.new()
    bm.from_mesh(me)
    kit.bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = kit.bpy.data.objects.new(name, me)
    kit.scene().collection.objects.link(o)
    return o, foot


def belly_under(x, y):
    dg = kit.bpy.context.evaluated_depsgraph_get()
    ok, loc, *_ = kit.scene().ray_cast(dg, Vector((x, y, 0.0)), Vector((0, 0, 1)))
    return loc.z if ok else 9.0


def nose_doors_shut(hide):
    """The nose bay's doors shut (LdgDrUp, shown only with the gear up): a panel over the opening the open doors
    leave in the belly (rays from below reach the bay's roof, 8 cm or more above the belly at |x| 0.5), its height
    across taken from the belly beside the opening. `hide`: the parts in the way (the open doors, the leg) while the rays look."""
    for o in hide:
        o.hide_viewport = True
    xs = [k / 40 for k in range(-18, 19)]
    ys = [k / 40 for k in range(120, 230)]
    side = {y: max(belly_under(-0.5, y), belly_under(0.5, y)) for y in ys}
    hole = [(x, y) for y in ys for x in xs if belly_under(x, y) > side[y] + 0.08]
    x0, x1 = min(h[0] for h in hole) - 0.02, max(h[0] for h in hole) + 0.02
    y0, y1 = min(h[1] for h in hole) - 0.02, max(h[1] for h in hole) + 0.02
    vs, faces, n = [], [], 8
    rows = [y0 + (y1 - y0) * j / 24 for j in range(25)]
    for y in rows:
        zl, zr = belly_under(x0 - 0.03, y), belly_under(x1 + 0.03, y)
        for i in range(n + 1):
            t = i / n
            vs.append((x0 + (x1 - x0) * t, y, (1 - t) * zl + t * zr - 0.004))
    for j in range(len(rows) - 1):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + n + 1, a + n + 2, a + 1))  # facing down
    for o in hide:
        o.hide_viewport = False
    me = kit.bpy.data.meshes.new("LdgDrUp")
    me.from_pydata(vs, [], faces)
    me.materials.append(kit.material("nose_door", DOOR_GREY, metallic=0.15, roughness=0.75))
    o = kit.bpy.data.objects.new("LdgDrUp", me)
    kit.scene().collection.objects.link(o)
    print("NOSE DOORS", round(x0, 3), round(x1, 3), round(y0, 3), round(y1, 3))
    return o


def main():
    m = kit.normalise(SRC, LENGTH)
    skin(m)
    markings()
    parts, rudders = cut_surfaces(m)
    bays, bay_hinges = cut_bays(m)
    parts.update(bays)
    # Gear: the legs (strut, brace, hub) and their wheels, which ride on them (WheelsA nose, WheelsB left, WheelsC
    # right: the original's wheel frame names) so the game can roll them; the doors (static, hidden once up).
    # Each wheel: its tyre and the loose pieces (hub, bolts) of its leg's meshes inside the tyre's box.
    def wheel(name, tyres, legs):
        vs = [t.matrix_world @ v.co for t in tyres for v in t.data.vertices]
        lo, hi = Vector(map(min, *vs)) - Vector((0.02,) * 3), Vector(map(max, *vs)) + Vector((0.02,) * 3)
        inside = lambda a, b: all(lo[i] <= a[i] and b[i] <= hi[i] for i in range(3))
        return kit.join([*tyres, kit.extract_loose(legs, inside, name + "_hub")], name)
    parts["WheelsA"] = wheel("WheelsA", [m["46"], m["47"]], [m["45"]])
    parts["WheelsB"] = wheel("WheelsB", [m["20"]], [m["19"]])
    parts["WheelsC"] = wheel("WheelsC", [m["67"]], [m[k] for k in ("66", "74", "75", "77", "79", "81", "83", "85",
                                                                     "87", "89", "91")])
    parts["LdgL"] = kit.join([m["18"], m["19"]], "LdgL")
    parts["LdgR"] = kit.join([m[k] for k in ("66", "68", "70", "72", "74", "75", "77", "79", "81", "83", "85", "87",
                                               "89", "91") if m[k].data.vertices], "LdgR")
    # The nose bay: the leg's pieces below the hinge, then what else hangs below the belly there. The download has
    # the nose doors open and the drag brace down; they are doors, so they join the main doors in LdgDr.
    # (The belly there lies at z 1.3-1.5: a piece reaching below 1.3 and no higher than 1.7 hangs out of the bay.)
    bay = lambda lo, hi: max(abs(lo.x), abs(hi.x)) < 0.4 and lo.y > 3.2 and hi.y < 5.8 and hi.z < 1.7 and lo.z < 1.3
    strut = kit.extract_loose([m["45"]], lambda lo, hi: bay(lo, hi) and lo.y > 4.4 and hi.y < 4.8 and lo.z < 1.05,
                              "nose_strut")
    nose_doors = kit.extract_loose([m[k] for k in ("37", "40", "43", "45")], bay, "nose_doors")
    parts["LdgDr"] = kit.join([m["64"], m["8"], nose_doors], "LdgDr")
    parts["LdgF"] = kit.join([m["44"], strut], "LdgF")
    # The download's nose tyres stand 6 cm above the main tyres' ground: the nose leg and its wheels go down onto it.
    drop = min(v.co.z for v in parts["WheelsA"].data.vertices)
    for k in ("LdgF", "WheelsA"):
        parts[k].data.transform(Matrix.Translation((0, 0, -drop)))
    parts["LdgDrUp"] = nose_doors_shut([parts[k] for k in ("LdgDr", "LdgF", "WheelsA")])
    pylon_objs, pylon_points = pylons()
    parts.update({o.name: o for o in pylon_objs.values()})
    # The download's cockpit has a HUD-like frame arch and glass ahead of the pilot and a glowing panel strip; the
    # F-35 has no HUD (its canopy bow is behind the pilot): drop them.
    for k in ("34", "54", "39", "27"):
        kit.bpy.data.objects.remove(m[k])
    # Canopy: the bubble; tinted blended glass.
    parts["canopy"] = kit.join([m["33"]], "canopy")
    glass = kit.material("canopy_glass", (0.35, 0.30, 0.18), roughness=0.1, alpha=0.4)
    for i, mat in enumerate(parts["canopy"].data.materials):
        if mat and mat.name.startswith("Whitish_grey"):
            parts["canopy"].data.materials[i] = glass
    parts["pilot"] = kit.pilot(EYE, colour=(0.33, 0.35, 0.28), helmet=(0.62, 0.63, 0.62))
    kit.decimate(m["52"], 0.08)  # the nozzle interior: 38k of the 83k triangles

    rest = [o for o in kit.scene().objects if o.type == 'MESH' and o.name not in parts]
    rig = kit.Rig(kit.join(rest, "f35i"), parts, ORIGIN)
    for s, n in ((1, "AilerR"), (-1, "AilerL")):
        rig.part(n, (2.27 * s, -3.73, 2.2), (s, 0, 0))
    for s, n in ((1, "ElevaR"), (-1, "ElevaL")):
        rig.part(n, (1.1 * s, -6.3, 2.27), (s, 0, 0))
    for n, (a, b) in rudders.items():
        rig.part(n, a, b - a)
    for n, (p, axis) in bay_hinges.items():
        rig.part(n, p, axis)
    # Gear legs fold forward (F-35A): the game turns LdgL by +g, LdgR and LdgF by -g (docs/aircraft.md §2.1); a
    # positive turn about +X swings a wheel below the hinge forward.
    rig.part("LdgL", (-2.05, -2.16, 1.95), (1, 0, 0))
    rig.part("LdgR", (2.05, -2.16, 1.95), (-1, 0, 0))
    rig.part("LdgF", (0.0, 4.55, 1.15), (-1, 0, 0))
    for n in ("LdgDr", "LdgDrUp", "canopy", "pilot", *(o.name for o in pylon_objs.values())):
        rig.place_centre(n)
    for wheel, leg in (("WheelsA", "LdgF"), ("WheelsB", "LdgL"), ("WheelsC", "LdgR")):
        rig.nest(wheel, leg)
    # Points: nozzle (radius 0.55 as the Y difference), gun (left shoulder), stations A..I (A / I the outboard
    # pylons (real stations 1 / 11), B / H the inboard heavy pylons (3 / 9), C / G the bays' air-to-ground (4 / 8)
    # and D / F their air-to-air stations (5 / 7), E the centreline (6): docs/f35i.md §3), wheel height, eye.
    rig.empty("EngineL", (0.0, -6.24, 1.94))
    rig.empty("EngineL1", (0.0, -6.24, 2.49))
    rig.empty("StationGun", (-0.75, 1.5, 2.45))
    bay_y = (BAY_Y[0] + BAY_Y[1]) / 2
    stations = [pylon_points["A"], pylon_points["B"], (-1.0, bay_y, 1.5), (-0.55, bay_y, 1.55), (0.0, bay_y, 1.0),
                (0.55, bay_y, 1.55), (1.0, bay_y, 1.5), pylon_points["H"], pylon_points["I"]]
    print("STATIONS", {k: tuple(round(c, 3) for c in p) for k, p in pylon_points.items()})
    for letter, p in zip("ABCDEFGHI", stations):
        rig.empty("Station" + letter, p)
    rig.empty("height", (0.0, ORIGIN.y, 0.0))  # lower case: the game finds it with find_child("height")
    rig.empty("Camera", EYE)
    tris = rig.export(os.path.join(OUT, "f35i.gltf"))
    print("RIGGED", OUT, "triangles", tris, "parts", sorted(parts))


main()
