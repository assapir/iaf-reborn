# Build a detailed F-16 model (Preferences -> Extras -> Models: Detailed; docs/aircraft-models.md §2): the F-16 base
# (base.py) with one variant layer, barak (the F-16D Barak, f16d.glb) or sufa (the F-16I Sufa, f16i.glb):
#
#   blender -b --python tools/f16/rig.py -- <FlightGear f16 checkout> <assets/converted/planes/f16/f16_h.gltf> \
#       <out.glb> barak|sufa
#
# F16D_FAST=1 skips the occlusion bake, F16D_DEBUG=1 prints every object's bounds, F16D_KEEP_PNG=1 keeps
# <out>.png.glb, the glb before the KTX2 pass (Blender reads it: tools/f16i/arm_front.py).
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..", "plane")]
LAYER = sys.argv[sys.argv.index("--") + 1:][3:4]
assert LAYER in (["barak"], ["sufa"]), "the variant layer: barak or sufa"
import base  # noqa: E402

base.build(importlib.import_module(LAYER[0]))
