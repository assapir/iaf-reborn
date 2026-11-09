# The F-35I's cockpit-view model (f35i_bc.gltf, docs/views.md §4.3 "Own jet in the cockpit views"): what the pilot
# sees of the own jet when looking aside or back. Built from the rigged model (tools/f35i/rig.py's f35i.gltf): the
# airframe aft of the eye (wings, spine, tails), without the canopy glass, pilot, gear and pylons; the canopy's rear
# frame arch and its side rails behind the eye (the panel, tools/f35i/cockpit3d.py, has them ahead of it), their own
# object f35i_bc_frame, which the 3D cockpit hides (it has its own, terrain_view.gd). Nothing ahead of the eye: the
# nose falls away under the glareshield. Same frame as f35i.gltf, so the game
# moves it by the descriptor's eye like the originals' *_bc.x.
#
#   blender -b --python tools/f35i/bc.py -- shared/extra/planes/f35i
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402

DIR = sys.argv[sys.argv.index("--") + 1]
CUT = 0.10  # model m behind the eye: the cut (the panel art shows everything ahead of the eye)
PRESENT_SCALE = 2.0
SEAT_FLOOR = 0.40  # model m under the eye: the downloaded model's seat is cut away above it, inside the sills
SEAT_HALF = 0.215  # model m either side (the sills 0.225 out; the skin outside them is kept)
SILL, CANOPY_HALF, DECK_END = 0.17, 0.36, 1.13  # model m: the sills under the eye, the canopy's half width, its end
SEAT_BACK = -0.60  # real m: the head box as modelled (its front 0.30 m behind the eye) moved back
# The aft deck's centre line (real m about the eye): level behind the eye, then from under the seat's head box up to
# the spine's front.
DECK = ((0, -0.22, -0.45), (0, -0.80, -0.42), (0, -DECK_END * PRESENT_SCALE - 0.04, 0.02))
# The canopy's frame arch, as cockpit3d.py's ARCH_Y, ARCH_TOP, ARCH_LEAN (real m about the eye).
ARCH_Y, ARCH_TOP, ARCH_LEAN = -0.42, 0.325, 0.28


def seat(eye):
    """Our Martin-Baker US16E seat behind the eye (real metres; docs/f35i.md §4.4): the dark head box (24 cm wide,
    tapering to its top) with the head pad on its front, the flared upper corners and two canopy breakers on top, the
    yellow warning tag on its side, the guide rails either side, and the back cushion down to the seat pan. The head
    box and rails stand SEAT_BACK further back than modelled (its front 0.90 m behind the eye; the real one right
    behind the helmet): the camera stays at the eye when the head turns, and nearer (0.30, 0.52, 0.70 m) the head
    box filled a quarter to half of the view looking back, a dark wall."""
    shell = kit.material("seat_shell", (0.030, 0.031, 0.034), roughness=0.6)
    pad = kit.material("seat_pad", (0.016, 0.016, 0.018), roughness=0.92)
    tag = kit.material("seat_tag", (0.80, 0.55, 0.02), roughness=0.5)
    head = [(0, -0.37, -0.30, 0.12, 0.07, 0.07), (0, -0.37, -0.05, 0.12, 0.075, 0.07),
            (0, -0.375, 0.12, 0.105, 0.07, 0.07), (0, -0.38, 0.19, 0.09, 0.06, 0.06),
            (0, -0.385, 0.215, 0.07, 0.045, 0.045), (0, -0.385, 0.225, 0.015, 0.01, 0.01)]
    out = [kit.loft("seat_headbox", shell, head, n=24, power=4.0),
           kit.box("seat_headpad", (0, -0.292, 0.07), (0.15, 0.03, 0.21), pad, bevel=0.012),
           kit.box("seat_tag", (0.118, -0.37, 0.04), (0.006, 0.05, 0.03), tag, bevel=0.002)]
    for s in (-1, 1):
        out.append(kit.box(f"seat_wing{s}", (s * 0.09, -0.315, 0.165), (0.03, 0.05, 0.08), shell, rot=(0, 0, s * 15),
                           bevel=0.01))
        out.append(kit.cyl(f"seat_breaker{s}", (s * 0.05, -0.33, 0.235), 0.007, 0.045, shell, rot=(-30, 0, 0),
                           verts=12))
        out.append(kit.box(f"seat_rail{s}", (s * 0.145, -0.42, -0.26), (0.03, 0.05, 0.72), shell, bevel=0.006))
    for o in out:
        o.location += Vector((0, SEAT_BACK, 0))
    # The cushion from the 3D cockpit's seat pan (its rear at the seat reference point, cockpit3d.py SRP) back under
    # the head box.
    out.append(kit.box("seat_back", (0, -0.55, -0.80), (0.30, 0.80, 0.08), pad, bevel=0.02))
    kit.deselect()
    for o in out:
        o.location += eye
        o.select_set(True)
    bpy.context.view_layer.objects.active = out[0]
    bpy.ops.object.convert(target='MESH')  # the bevels applied at real size, before the half-size scale
    return out


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    eye_g = json.load(open(os.path.join(DIR, "aircraft.json")))["eye"]  # glTF frame: +Y up, -Z nose
    eye = Vector((eye_g[0], -eye_g[2], eye_g[1]))  # Blender: Z up, +Y nose
    bpy.ops.import_scene.gltf(filepath=os.path.join(DIR, "f35i.gltf"))
    drop = ("canopy", "pilot", "Ldg", "Wheels", "Pylon")
    meshes = []
    for o in list(kit.scene().objects):
        if o.type == 'MESH' and not o.name.startswith(drop):
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
            meshes.append(o)
    for o in list(kit.scene().objects):
        if o not in meshes:
            bpy.data.objects.remove(o)
    kit.bake_transforms(meshes)
    body = kit.join(meshes, "f35i_bc")
    kit.bake_transforms([body])
    # Cut at the plane CUT behind the eye and keep the aft part; inside the canopy's reach (around the seat) keep
    # only what is below the sill, so the downloaded model's cockpit tub does not wrap the eye.
    ycut = eye.y - CUT
    kit.bisect([body], lambda c: True, (0, ycut, 0), (0, 1, 0))
    # The seat's box cut clean first (its faces are large: by their centres alone the cut left tall slivers standing
    # behind the rails until 2026-11-09).
    near = lambda c: c.y > eye.y - DECK_END and abs(c.x) < CANOPY_HALF + 0.1  # noqa: E731
    for co, no in (((0, 0, eye.z - SEAT_FLOOR), (0, 0, 1)), ((0, 0, eye.z - SILL), (0, 0, 1)),
                   ((0, eye.y - DECK_END, 0), (0, 1, 0)), ((CANOPY_HALF, 0, 0), (1, 0, 0)),
                   ((-CANOPY_HALF, 0, 0), (1, 0, 0)), ((SEAT_HALF, 0, 0), (1, 0, 0)), ((-SEAT_HALF, 0, 0), (1, 0, 0))):
        kit.bisect([body], near, co, no)
    # Ahead of the cut nothing is kept: the F-35's nose falls away under the glareshield (docs/f35i.md §4.1). Until
    # 2026-11-09 the fuselage ahead of the eye was an object of its own, f35i_bc_nose, seen over the glareshield.
    # Under the canopy back to the spine (DECK_END) everything over the sills goes (CANOPY_HALF either side: the
    # downloaded model's canopy frame and fairings stood there as grey blocks beside the rails until 2026-11-09), and
    # inside the cockpit's walls (SEAT_HALF) everything down to SEAT_FLOOR: its seat and tub (ours replace them).
    def dropped(f):
        p = f.calc_center_median() - eye
        return p.y > -CUT or (p.y > -DECK_END and (abs(p.x) < CANOPY_HALF and p.z > -SILL
                                                     or abs(p.x) < SEAT_HALF and p.z > -SEAT_FLOOR))

    bm = bmesh.new()
    bm.from_mesh(body.data)
    gone = [f for f in bm.faces if dropped(f)]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(body.data)
    bm.free()

    # Ours: the canopy's frame arch and the side rails behind the eye. The rails lie on the airframe's sills, as the
    # panel's (cockpit3d.py RAIL); the arch is cockpit3d.py's (ARCH_*, which also draws it for the 3D cockpit).
    dark = kit.material("bc_frame", (0.055, 0.057, 0.062), roughness=0.5)
    band = kit.material("bc_arch", (0.013, 0.013, 0.015), roughness=0.9)  # the arch: matte, as the glareshield
    # Ours too, in both cockpits (the body's): the side walls under the rails, as the 3D cockpit's (cockpit3d.py
    # WALL_PROFILE), and the aft deck under the canopy behind the seat, rising to the spine (inferred: the photos
    # show a dark deck there, docs/f35i.md §4.4).
    paint = kit.material("bc_wall", (0.030, 0.032, 0.036), roughness=0.62)
    inside = []
    for s in (-1, 1):
        rail = [eye + Vector(p) for p in ((s * 0.47, -CUT + 0.05, -0.36), (s * 0.46, -0.6, -0.35),
                                          (s * 0.44, -1.1, -0.32), (s * 0.43, -DECK_END * PRESENT_SCALE, -0.30))]
        kit.sweep(f"rail{s}", dark, kit.rounded_rect(0.085, 0.060, 0.022), [tuple(p) for p in rail])
        inside.append(kit.sweep(f"wall{s}", paint, [(u, v - 0.23) for u, v in kit.rounded_rect(0.03, 0.40, 0.004)],
                                [tuple(p) for p in rail]))
    deck = [(u, 0.09 * (1 - (u / 0.45) ** 2)) for u in np.linspace(0.45, -0.45, 13)] + [(-0.45, -0.05), (0.45, -0.05)]
    # The deck dark matte, as the sills and consoles read (the wall paint took the sun light grey there), with the
    # canopy actuator's fairing along its crown and a panel seam across it (inferred).
    matte = kit.material("bc_deck", (0.012, 0.012, 0.014), roughness=0.92)
    inside.append(kit.sweep("deck", matte, deck, [tuple(eye + Vector(p)) for p in DECK]))
    inside.append(kit.sweep("deck_fairing", matte, [(u, v + 0.095) for u, v in kit.rounded_rect(0.11, 0.05, 0.02)],
                            [tuple(eye + Vector(p)) for p in DECK[1:]]))
    seam = kit.material("bc_seam", (0.004, 0.004, 0.005), roughness=0.9)
    t = 0.45  # the seam's place along the ramp
    p = Vector(DECK[1]).lerp(Vector(DECK[2]), t)
    inside.append(kit.sweep("deck_seam", seam, [(0.003 * math.cos(a), 0.003 * math.sin(a)) for a in
                                                 np.linspace(0, 2 * math.pi, 6, endpoint=False)],
                            [tuple(eye + p + Vector((u, 0, 0.09 * (1 - (u / 0.45) ** 2) + 0.005)))
                             for u in np.linspace(-0.44, 0.44, 13)], ref=(0, 1, 0)))
    arch = [tuple(eye + Vector((0.46 * math.sin(a), ARCH_Y + ARCH_LEAN * math.cos(a),
                                -0.34 + (ARCH_TOP + 0.34) * math.cos(a))))
            for a in np.linspace(-math.pi / 2, math.pi / 2, 33)]
    kit.sweep("arch", band, kit.rounded_rect(0.045, 0.09, 0.014), arch, ref=(0, 1, 0))
    seat_parts = seat(eye) + inside
    # Modelled in real metres around the eye, like the panel art; the game draws the jet at the Present scale (2.0,
    # docs/adding-a-plane.md §2), so they shrink by half about the eye to come out real size.
    parts = [o for o in kit.scene().objects if o.type == 'MESH' and o is not body]
    k = Matrix.Translation(eye) @ Matrix.Scale(1.0 / PRESENT_SCALE, 4) @ Matrix.Translation(-eye)
    for o in parts:
        o.matrix_world = k @ o.matrix_world
    kit.bake_transforms(parts)
    # The seat is the body's (both cockpits show it; the 3D cockpit hides the frame for its own).
    body = kit.join([body] + seat_parts, "f35i_bc")
    frame = kit.join([o for o in parts if o not in seat_parts], "f35i_bc_frame")
    for o in kit.scene().objects:
        o.select_set(o in (body, frame))
    bpy.ops.export_scene.gltf(filepath=os.path.join(DIR, "f35i_bc.gltf"), export_format='GLTF_SEPARATE',
                              export_yup=True, use_selection=True, export_apply=True, export_texture_dir="textures")
    print(*(f"{o.name} {sum(len(p.vertices) - 2 for p in o.data.polygons)}" for o in (body, frame)))


main()
