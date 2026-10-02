# The F-35I cockpit panel, modelled and rendered (docs/f35i.md §4) with tools/plane/kit.py: a 3D cockpit in metres
# around the pilot's eye after the public-domain F-35 cockpit photos (docs/f35i.md §5), rendered with the game's
# cockpit camera into the panel strip. The same camera places the live parts, written into cockpit.json: the
# panoramic display's four MFD portals edge to edge (one display), its lower windows (fuel, chaff / flares, text),
# the standby ADI (a holdout window), the helmet HUD on the nose axis, and the F-16's lamps and gear lever
# (borrowed at run time through "Shared": "f16", never committed) on the bays modelled for them.
#
#   blender -b --python tools/f35i/cockpit3d.py -- <cockpit dir>          (LAYOUT_ONLY=1: cockpit.json only)
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
# As the original jets (F-16 190): the forward view shows 162 rows of the panel. CENTRE_ROW is the projection
# centre's panel row for it, measured in the game (cockpit.projection_centre() - panel_top(), original px).
MAIN_OFFSET_Y = 190.0
CENTRE_ROW = float(os.environ.get("CENTRE_ROW", "-46"))

TILT = 18.0  # the panel face leans back (deg)
FACE_Y, FACE_Z = 0.66, -0.25  # the face passes through (0, FACE_Y, FACE_Z)
PCD = (0.508, 0.203)  # the panoramic display (20 x 8 in)
PCD_TOP = -0.135


def on_face(x, z, depth=0.0):
    """A point on the panel face at lateral x, height z; `depth` toward the pilot along its normal."""
    t = math.radians(TILT)
    return (x, FACE_Y + (z - FACE_Z) * math.tan(t) - depth * math.cos(t), z + depth * math.sin(t))


FACE_ROT = (-TILT, 0, 0)
KNOB_ROT = (90 - TILT, 0, 0)  # a cylinder's axis along the face normal

# Lamp bays on the face beside the display: name -> (x, z, w, h); the F-16 lamps are centred on them.
BAYS = {"caution": (0.315, -0.170, 0.058, 0.058), "fire": (0.315, -0.238, 0.048, 0.046),
        "lamps": (0.315, -0.305, 0.054, 0.060), "gear": (-0.320, -0.220, 0.040, 0.118),
        "gear_lamps": (-0.268, -0.168, 0.036, 0.030), "flap": (-0.268, -0.207, 0.036, 0.016)}
# Lamp -> (bay, dx, dz) inside it.
LAMPS = {"LIGHT000": ("caution", 0, 0), "LIGHT001": ("fire", 0, 0), "LIGHT008": ("lamps", 0, 0.021),
         "LIGHT005": ("lamps", 0, 0.007), "LIGHT006": ("lamps", 0, -0.007), "LIGHT003": ("lamps", -0.016, -0.021),
         "LIGHT004": ("lamps", 0.016, -0.021), "LIGHT009": ("gear", 0, 0), "SLIGHT000": ("gear_lamps", 0, 0.007),
         "SLIGHT001": ("gear_lamps", -0.011, -0.007), "SLIGHT002": ("gear_lamps", 0.011, -0.007),
         "SLIGHT003": ("flap", 0, 0)}


def build():
    m = kit.material
    paint = m("panel_paint", (0.055, 0.058, 0.064), roughness=0.62, grain=0.08)
    black = m("antiglare", (0.016, 0.016, 0.018), roughness=0.85, grain=0.05)
    bezel = m("bezel", (0.03, 0.031, 0.034), roughness=0.35)
    glass = m("pcd_glass", (0.004, 0.005, 0.007), roughness=0.06)
    frame = m("window_frame", (0.035, 0.04, 0.045), roughness=0.4)
    knob = m("knob", (0.02, 0.02, 0.022), roughness=0.45)
    alu = m("alu", (0.55, 0.56, 0.58), metallic=1.0, roughness=0.35)
    sill = m("sill", (0.07, 0.072, 0.078), roughness=0.5, grain=0.05)
    grip = m("grip", (0.035, 0.035, 0.037), roughness=0.7)
    bay = m("lamp_bay", (0.012, 0.012, 0.013), roughness=0.5)
    hold = m("esis_hole", (0, 0, 0), holdout=True)
    box, cyl = kit.box, kit.cyl

    box("face", on_face(0, -0.31, -0.02), (1.02, 0.04, 0.42), paint, rot=FACE_ROT, bevel=0.008)
    # The display: bezel, glass, the eight lower windows' frames.
    pz = PCD_TOP - PCD[1] / 2
    box("pcd_bezel", on_face(0, pz, 0.012), (PCD[0] + 0.022, 0.02, PCD[1] + 0.022), bezel, rot=FACE_ROT, bevel=0.006)
    box("pcd_glass", on_face(0, pz, 0.0225), (PCD[0], 0.002, PCD[1]), glass, rot=FACE_ROT, bevel=0)
    gl, gw = PCD_TOP - PCD[1], PCD[0]
    for i in range(8):
        cx = -gw / 2 + gw / 8 * (i + 0.5)
        for dx, dz, sx, sz in ((0, 0.024, gw / 8 - 0.008, 0.0015), (0, -0.024, gw / 8 - 0.008, 0.0015),
                               (-(gw / 16 - 0.004), 0, 0.0015, 0.048), (gw / 16 - 0.004, 0, 0.0015, 0.048)):
            box(f"win{i}_{dx}_{dz}", on_face(cx + dx, gl + 0.032 + dz, 0.0245), (sx, 0.001, sz), frame, rot=FACE_ROT, bevel=0)
    # The glareshield: an arched hood over the display, its rear edge just ahead of the display's top so it does
    # not hide it from the eye, sloping down to the sides; and its skirt down to the display.
    kit.arch("glareshield", black, width=0.86, rise=0.035, y0=0.705, y1=0.98, z=-0.118, thickness=0.03)
    box("glareshield_skirt", on_face(0, PCD_TOP + 0.02, 0.016), (0.78, 0.03, 0.04), black, rot=FACE_ROT, bevel=0.008)
    # Under the display: the control strip and the standby display (a holdout: the game's ADI shows through).
    box("icp", on_face(0, -0.39, 0.012), (0.36, 0.022, 0.07), bezel, rot=FACE_ROT, bevel=0.005)
    box("esis", on_face(0, -0.39, 0.026), (0.075, 0.006, 0.058), hold, rot=FACE_ROT, bevel=0)
    for i, x in enumerate((-0.15, -0.11, -0.07, 0.07, 0.11, 0.15)):
        cyl(f"icp_knob{i}", on_face(x, -0.385, 0.032), 0.009, 0.016, knob, rot=KNOB_ROT)
        cyl(f"icp_cap{i}", on_face(x, -0.385, 0.041), 0.004, 0.003, alu, rot=KNOB_ROT)
    for name, (x, z, w, h) in BAYS.items():
        box(f"bay_{name}", on_face(x, z, 0.012), (w, 0.016, h), bay, rot=FACE_ROT, bevel=0.003)
    for side in (-1, 1):
        for i in range(4):
            cyl(f"sw{side}_{i}", on_face(side * 0.39, -0.15 - i * 0.05, 0.03), 0.007, 0.02, knob, rot=KNOB_ROT)
    # Side walls with switch panels, consoles, the throttle (left) and the side-stick (right).
    for s in (-1, 1):
        box(f"wall{s}", (s * 0.52, 0.15, -0.34), (0.03, 1.2, 0.24), paint, bevel=0.006)
        for i, (y, z) in enumerate(((0.52, -0.27), (0.38, -0.27), (0.24, -0.27), (0.52, -0.37), (0.38, -0.37))):
            box(f"wpanel{s}_{i}", (s * 0.503, y, z), (0.006, 0.12, 0.08), bezel, bevel=0.003)
            for j in range(3):
                cyl(f"wknob{s}_{i}_{j}", (s * 0.497, y + (j - 1) * 0.035, z + 0.012), 0.007, 0.012, knob, rot=(0, 90, 0))
                box(f"wtog{s}_{i}_{j}", (s * 0.496, y + (j - 1) * 0.035, z - 0.022), (0.006, 0.006, 0.014), alu, bevel=0.001)
        box(f"console{s}", (s * 0.40, 0.18, -0.47), (0.22, 0.85, 0.10), paint, bevel=0.01)
        for i in range(5):
            box(f"cpanel{s}_{i}", (s * 0.40, 0.48 - i * 0.13, -0.418), (0.17, 0.10, 0.006), bezel, bevel=0.002)
            for j in range(3):
                cyl(f"csw{s}_{i}_{j}", (s * 0.40 + (j - 1) * 0.045, 0.48 - i * 0.13, -0.41), 0.006, 0.012, knob, rot=(0, 0, 0))
        # The canopy's frame along each side: a heavy rail on the sill rising a little toward the glareshield's
        # front corners (the F-35's one-piece canopy has no windscreen arch in front; its metal bow is behind the
        # pilot's head, out of the forward view).
        box(f"sill{s}", (s * 0.54, 0.15, -0.20), (0.07, 1.2, 0.05), sill, bevel=0.012)
        box(f"canopy_frame{s}", (s * 0.505, 0.62, -0.135), (0.05, 0.36, 0.05), sill, rot=(-11, 0, s * 8), bevel=0.014)
        box(f"rail{s}", (s * 0.515, 0.15, -0.172), (0.012, 1.2, 0.006), alu, bevel=0.002)
    box("throttle_base", (-0.38, 0.10, -0.40), (0.07, 0.16, 0.05), grip, bevel=0.01)
    box("throttle", (-0.38, 0.13, -0.33), (0.05, 0.09, 0.11), grip, rot=(-12, 0, 0), bevel=0.018)
    cyl("stick", (0.36, 0.08, -0.36), 0.018, 0.10, grip, rot=(0, 0, 0))
    box("stick_grip", (0.36, 0.085, -0.29), (0.045, 0.05, 0.075), grip, rot=(-8, 0, 0), bevel=0.016)


def layout(cam):
    px = lambda p: kit.panel_px(cam, p)
    g = lambda dx, dz: px(on_face(dx, PCD_TOP - PCD[1] / 2 + dz, 0.0235))
    tl, tr, bl, br = g(-PCD[0] / 2, PCD[1] / 2), g(PCD[0] / 2, PCD[1] / 2), g(-PCD[0] / 2, -PCD[1] / 2), g(PCD[0] / 2, -PCD[1] / 2)
    x0, x1, y0 = max(tl.x, bl.x) + 1, min(tr.x, br.x) - 1, tl.y + 1
    portal_list, k = kit.portals(x0, x1, y0, [2, 3, 1, 7])
    win_top = px(on_face(0, PCD_TOP - PCD[1] + 0.056, 0.0245)).y
    strip = win_top + 4
    w8 = (x1 - x0) / 8
    sec = {"MFD": {"Portals": portal_list},
           "FUELDIGITAL": {"Active": 1.0, "ColorR": 64.0, "ColorG": 200.0, "ColorB": 40.0,
                           "OffsetX": round(x0 + w8 / 2 - 15, 1), "OffsetY": round(strip + 4, 1)},
           # chaff / flares ("%03d", Arial h10 ~ 18 px wide): centred in the last window
           "CHAFF": {"OffX": round(x0 + w8 * 7.5 - 9, 1), "OffY": round(strip, 1)},
           "FLARE": {"OffX": round(x0 + w8 * 7.5 - 9, 1), "OffY": round(strip + 12, 1)},
           "TEXTMESSAGE": {"LengthChar": 30.0, "OffsetX1": round(x0 + w8 + 6, 1), "OffsetY1": round(strip, 1),
                           "OffsetX2": round(x0 + w8 + 6, 1), "OffsetY2": round(strip + 12, 1)}}
    e, er = px(on_face(0, -0.39, 0.03)), px(on_face(0.0375, -0.39, 0.03))
    sec["LENHORIZON"] = {"Active": 1.0, "FileName": "F16adi.bmp", "CenterX": round(e.x, 1), "CenterY": round(e.y, 1),
                         "Factor": 15.0, "Radius": round(min(er.x - e.x, 26.0), 1)}
    centres = {}
    for key, (bay, dx, dz) in LAMPS.items():
        bx, bz = BAYS[bay][:2]
        c = px(on_face(bx + dx, bz + dz, 0.021))
        centres[key] = (c.x, c.y)
    sec.update(kit.lamp_sections(centres))
    # The helmet HUD: the boresight on the nose axis, the field centre 47 px and the gun cross 5 px lower, as the
    # F-16's ([HUD] rows count up from the panel's top).
    nose = px((0, 10, 0))
    hud = {"BorePositionY": round(-nose.y, 1), "CenterY": round(-nose.y - 47, 1), "GunRetPositionY": round(-nose.y - 5, 1)}
    return sec, hud, k


def main():
    kit.bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    cam = kit.cockpit_camera(CENTRE_ROW)
    sec, hud, k = layout(cam)
    print("PORTALS", sec["MFD"]["Portals"], "scale", k, "HUD", hud, "ADI", sec["LENHORIZON"])
    if not os.environ.get("LAYOUT_ONLY"):
        kit.render_panel(os.path.join(OUT_DIR, "f35panel.png"))
    kit.update_cockpit_json(os.path.join(OUT_DIR, "cockpit.json"), sec, hud, MAIN_OFFSET_Y)


main()
