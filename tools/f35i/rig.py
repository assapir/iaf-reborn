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
from mathutils import Vector  # noqa: E402

SRC, OUT = sys.argv[sys.argv.index("--") + 1:][:2]
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
LENGTH = 15.67  # m (Lockheed Martin)
ORIGIN = Vector((0.0, -1.0, 1.85))  # the aircraft origin (≈ centre of gravity): the game's rig position
EYE = Vector((0.0, 4.1, 3.0))  # in the seat, at seated head height under the canopy (the helmet clears the rim)
SKIN_GREY = (0.37, 0.39, 0.41)  # F-35 low-observable grey, matte (sRGB, before the baked shading)
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
    kit.decal("roundel_wing_upper_left", rnd, (-3.6, -2.7, 10), (0, 0, -1), 0.8, 0.8, (0, 1, 0))
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


def main():
    m = kit.normalise(SRC, LENGTH)
    skin(m)
    markings()
    parts, rudders = cut_surfaces(m)
    # Gear: main legs (wheel, strut, brace, hub), the doors (static, hidden once up), the nose leg.
    parts["LdgL"] = kit.join([m[k] for k in ("18", "19", "20")], "LdgL")
    parts["LdgR"] = kit.join([m[k] for k in ("66", "67", "68", "70", "72", "74", "75", "77", "79", "81", "83", "85",
                                               "87", "89", "91")], "LdgR")
    parts["LdgDr"] = kit.join([m["64"], m["8"]], "LdgDr")
    strut = kit.extract([m["45"]], lambda c: 4.0 < c.y < 5.2 and c.z < 1.05 and abs(c.x) < 0.3, "nose_strut")
    parts["LdgF"] = kit.join([m["44"], m["46"], m["47"], strut], "LdgF")
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
    # Gear legs fold forward (F-35A): the game turns LdgL by +g, LdgR and LdgF by -g (docs/aircraft.md §2.1); a
    # positive turn about +X swings a wheel below the hinge forward.
    rig.part("LdgL", (-2.05, -2.16, 1.95), (1, 0, 0))
    rig.part("LdgR", (2.05, -2.16, 1.95), (-1, 0, 0))
    rig.part("LdgF", (0.0, 4.55, 1.15), (-1, 0, 0))
    for n in ("LdgDr", "canopy", "pilot"):
        rig.place_centre(n)
    # Points: nozzle (radius 0.55 as the Y difference), gun (left shoulder), stations A..I (A / I wing tips, B / H
    # wings, C / G the bays' outboard and D / F inboard stations, E centre: player_aircraft.gd f35i_object), wheel
    # height, eye.
    rig.empty("EngineL", (0.0, -6.24, 1.94))
    rig.empty("EngineL1", (0.0, -6.24, 2.49))
    rig.empty("StationGun", (-0.75, 1.5, 2.45))
    stations = [(-5.2, -2.9, 2.05), (-3.4, -2.4, 2.0), (-1.15, -2.7, 1.3), (-0.55, -2.4, 1.25), (0.0, -0.5, 1.2),
                (0.55, -2.4, 1.25), (1.15, -2.7, 1.3), (3.4, -2.4, 2.0), (5.2, -2.9, 2.05)]
    for letter, p in zip("ABCDEFGHI", stations):
        rig.empty("Station" + letter, p)
    rig.empty("height", (0.0, ORIGIN.y, 0.0))  # lower case: the game finds it with find_child("height")
    rig.empty("Camera", EYE)
    tris = rig.export(os.path.join(OUT, "f35i.gltf"))
    print("RIGGED", OUT, "triangles", tris, "parts", sorted(parts))


main()
