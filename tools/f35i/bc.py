# The F-35I's cockpit-view model (f35i_bc.gltf, docs/views.md §4.3 "Own jet in the cockpit views"): what the pilot
# sees of the own jet when looking aside or back. Built from the rigged model (tools/f35i/rig.py's f35i.gltf): the
# airframe aft of the eye (wings, spine, tails), without the canopy glass, pilot and gear, plus the canopy's rear
# frame arch and its side rails behind the eye (the panel art, tools/f35i/cockpit3d.py, has them
# ahead of it). Same frame as f35i.gltf, so the game moves it by the descriptor's eye like the originals' *_bc.x.
#
#   blender -b --python tools/f35i/bc.py -- game/extra/planes/f35i
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


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    eye_g = json.load(open(os.path.join(DIR, "aircraft.json")))["eye"]  # glTF frame: +Y up, -Z nose
    eye = Vector((eye_g[0], -eye_g[2], eye_g[1]))  # Blender: Z up, +Y nose
    bpy.ops.import_scene.gltf(filepath=os.path.join(DIR, "f35i.gltf"))
    drop = ("canopy", "pilot", "Ldg")
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
    bm = bmesh.new()
    bm.from_mesh(body.data)
    gone = [f for f in bm.faces if f.calc_center_median().y > ycut
            or (abs(f.calc_center_median().x) < 0.30 and f.calc_center_median().y > eye.y - 0.8
                and f.calc_center_median().z > eye.z - 0.15)]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(body.data)
    bm.free()

    # Ours: the canopy's rear frame arch and the side rails behind the eye (the seat's head box, right behind the
    # eye, would fill the view: the camera stays at the eye when the head turns).
    dark = kit.material("bc_frame", (0.055, 0.057, 0.062), roughness=0.5)
    for s in (-1, 1):
        rail = [eye + Vector(p) for p in ((s * 0.47, -CUT + 0.05, -0.23), (s * 0.46, -0.6, -0.23), (s * 0.42, -1.1, -0.20))]
        kit.sweep(f"rail{s}", dark, kit.rounded_rect(0.085, 0.060, 0.022), [tuple(p) for p in rail])
    # The arch: the canopy's rear frame, over the head box from rail to rail.
    arch = []
    for a in np.linspace(-math.pi / 2, math.pi / 2, 25):
        arch.append(tuple(eye + Vector((0.46 * math.sin(a), -0.75 - 0.05 * math.cos(a), -0.21 + 0.42 * math.cos(a)))))
    kit.sweep("arch", dark, kit.rounded_rect(0.07, 0.05, 0.018), arch)
    # Modelled in real metres around the eye, like the panel art; the game draws the jet at the Present scale (2.0,
    # docs/adding-a-plane.md §2), so they shrink by half about the eye to come out real size.
    parts = [o for o in kit.scene().objects if o.type == 'MESH' and o is not body]
    k = Matrix.Translation(eye) @ Matrix.Scale(1.0 / PRESENT_SCALE, 4) @ Matrix.Translation(-eye)
    for o in parts:
        o.matrix_world = k @ o.matrix_world
    kit.bake_transforms(parts)
    body = kit.join([body] + parts, "f35i_bc")
    for o in kit.scene().objects:
        o.select_set(o is body)
    bpy.ops.export_scene.gltf(filepath=os.path.join(DIR, "f35i_bc.gltf"), export_format='GLTF_SEPARATE',
                              export_yup=True, use_selection=True, export_apply=True, export_texture_dir="textures")
    print("BC triangles", sum(len(p.vertices) - 2 for p in body.data.polygons))


main()
