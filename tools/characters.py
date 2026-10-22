"""Procedural low-poly heroes for VX.

Three ToME4-inspired classes:
  * warrior       - Berserker / Bulwark: plate, crimson cape, greatsword, kite shield
  * archmage      - Archmage: pointed hat, robe, staff with an elemental orb
  * chronomancer  - Paradox Mage: hooded violet robes, clockwork, hourglass staff

The models are authored at roughly 1 unit tall, Y up, facing +Z. Every triangle
is assigned to a joint; the exporter turns that into a .vxm file with a small
skeleton so the engine can animate limbs.
"""
from __future__ import annotations

import json
import math
import os
from collections import OrderedDict

from geometry import Builder, compute_joint_world

# ---------------------------------------------------------------------------
# material palette (sRGB)
# ---------------------------------------------------------------------------

MATS = {
    "steel_dark":      ((58, 64, 76), False),
    "steel":           ((110, 120, 136), False),
    "steel_light":     ((162, 172, 188), False),
    "steel_white":     ((206, 214, 224), False),
    "gold":            ((234, 166, 46), False),
    "gold_light":      ((255, 212, 94), False),
    "bronze":          ((176, 120, 56), False),
    "leather":         ((90, 64, 48), False),
    "leather_light":   ((122, 90, 63), False),
    "crimson":         ((140, 39, 51), False),
    "crimson_light":   ((184, 58, 69), False),
    "crimson_dark":    ((94, 25, 34), False),
    "skin":            ((214, 178, 148), False),
    "skin_shadow":     ((176, 132, 101), False),
    "eye_dark":        ((24, 22, 30), False),
    "navy":            ((43, 74, 140), False),
    "navy_light":      ((74, 122, 196), False),
    "navy_deep":       ((27, 44, 90), False),
    "beard_white":     ((230, 235, 242), False),
    "violet":          ((93, 52, 136), False),
    "violet_light":    ((138, 84, 189), False),
    "violet_dark":     ((61, 32, 88), False),
    "silver":          ((184, 191, 204), False),
    "cyan":            ((53, 184, 176), False),
    "cyan_dark":       ((23, 82, 89), False),
    "fire":            ((255, 159, 28), True),
    "flame":           ((255, 212, 94), True),
    "glow_cyan":       ((111, 224, 208), True),
    "glow_blue":       ((127, 179, 239), True),
    "bone":            ((226, 214, 188), False),
    "wood":            ((122, 90, 63), False),
    "wood_dark":       ((78, 56, 40), False),
    "iron":            ((74, 82, 94), False),
}

# ---------------------------------------------------------------------------
# skeleton
# ---------------------------------------------------------------------------

BASE_JOINTS = [
    ("root", None, (0.0, 0.0, 0.0)),
    ("hips", "root", (0.0, 0.44, 0.0)),
    ("torso", "hips", (0.0, 0.06, 0.0)),
    ("head", "torso", (0.0, 0.27, 0.0)),
    ("arm_l", "torso", (0.17, 0.23, 0.0)),
    ("arm_r", "torso", (-0.17, 0.23, 0.0)),
    ("cape", "torso", (0.0, 0.23, -0.075)),
    ("leg_l", "hips", (0.075, 0.0, 0.0)),
    ("leg_r", "hips", (-0.075, 0.0, 0.0)),
    ("weapon", "arm_r", (0.0, -0.30, 0.02)),
    ("offhand", "arm_l", (0.0, -0.30, 0.02)),
]


def joints_with(extra):
    return BASE_JOINTS + extra


# ---------------------------------------------------------------------------
# shared body
# ---------------------------------------------------------------------------

def add_body(b, cfg, hide_legs=False):
    skin = cfg["skin"]
    armor = cfg["leg_armor"]
    boot = cfg["boot"]
    torso_mat = cfg["torso"]
    belt = cfg["belt"]
    accent = cfg["accent"]

    # pelvis + belt
    b.taper_box("hips", armor, (0.0, 0.455, 0.0), 0.10, (0.100, 0.078), (0.095, 0.074))
    b.box("hips", belt, (0.0, 0.497, 0.0), (0.205, 0.030, 0.158))
    b.box("hips", "gold", (0.0, 0.497, 0.079), (0.045, 0.036, 0.014))
    b.box("hips", accent, (0.0, 0.475, 0.080), (0.022, 0.050, 0.012))

    # chest
    b.taper_box("torso", torso_mat, (0.0, 0.630, 0.0), 0.265, (0.098, 0.070), (0.148, 0.086))
    b.box("torso", cfg["chest"], (0.0, 0.635, 0.076), (0.205, 0.185, 0.026))
    b.box("torso", belt, (0.0, 0.525, 0.0), (0.196, 0.028, 0.150))
    b.box("torso", "gold", (0.0, 0.525, 0.077), (0.036, 0.030, 0.010))
    # tabard hanging over the hips
    b.taper_box("torso", accent, (0.0, 0.415, 0.083), 0.20, (0.062, 0.010), (0.078, 0.012))
    b.box("torso", "gold", (0.0, 0.318, 0.085), (0.140, 0.014, 0.014))
    # shoulder yoke
    b.box("torso", cfg["chest"], (0.0, 0.748, 0.0), (0.292, 0.040, 0.150))
    b.box("torso", "gold", (0.0, 0.763, 0.0), (0.300, 0.014, 0.140))

    # neck + head
    b.frustum("head", skin, (0.0, 0.775, 0.0), 0.033, 0.030, 0.055, 8)
    b.sphere("head", skin, (0.0, 0.848, 0.010), 0.083, 10, 5, (0.92, 1.04, 0.96))
    b.box("head", "skin_shadow", (0.0, 0.838, 0.092), (0.018, 0.030, 0.024))
    b.box("head", "eye_dark", (0.031, 0.861, 0.086), (0.015, 0.017, 0.010))
    b.box("head", "eye_dark", (-0.031, 0.861, 0.086), (0.015, 0.017, 0.010))
    b.box("head", "skin_shadow", (0.0, 0.820, 0.090), (0.036, 0.009, 0.008))

    # arms
    for side, sx in (("l", 1.0), ("r", -1.0)):
        part = "arm_" + side
        b.box(part, cfg["pauldron"], (sx * 0.190, 0.742, 0.0), (0.105, 0.052, 0.130))
        b.frustum(part, cfg["sleeve"], (sx * 0.190, 0.660, 0.0), 0.046, 0.042, 0.155, 7,
                  rot=(0.0, 0.0, -sx * 0.06))
        b.frustum(part, cfg["sleeve"], (sx * 0.190, 0.535, 0.0), 0.041, 0.036, 0.140, 7,
                  rot=(0.0, 0.0, -sx * 0.04))
        b.box(part, cfg["glove"], (sx * 0.190, 0.452, 0.010), (0.058, 0.066, 0.064))
        b.box(part, "gold", (sx * 0.190, 0.598, 0.0), (0.078, 0.016, 0.080))

    if not hide_legs:
        for side, sx in (("l", 1.0), ("r", -1.0)):
            part = "leg_" + side
            b.frustum(part, cfg["leg_armor"], (sx * 0.078, 0.350, 0.0), 0.056, 0.052, 0.180, 7)
            b.frustum(part, cfg["leg_armor"], (sx * 0.078, 0.170, 0.004), 0.048, 0.042, 0.160, 7)
            b.box(part, cfg["knee"], (sx * 0.078, 0.255, 0.050), (0.090, 0.052, 0.028))
            b.taper_box(part, boot, (sx * 0.078, 0.045, 0.022), 0.090, (0.053, 0.087), (0.045, 0.066))
            b.box(part, "gold", (sx * 0.078, 0.096, 0.022), (0.092, 0.012, 0.120))
    else:
        for side, sx in (("l", 1.0), ("r", -1.0)):
            part = "leg_" + side
            b.frustum(part, cfg["boot"], (sx * 0.075, 0.34, 0.0), 0.050, 0.045, 0.14, 6)
            b.frustum(part, cfg["boot"], (sx * 0.075, 0.19, 0.0), 0.042, 0.038, 0.13, 6)
            b.box(part, cfg["boot"], (sx * 0.075, 0.045, 0.020), (0.090, 0.090, 0.150))

    add_cape(b, cfg)


def add_cape(b, cfg):
    z = -0.078
    y = 0.742
    widths = (0.104, 0.120, 0.140, 0.162)
    depth = 0.011
    seg_h = 0.158
    for i in range(4):
        cy = y - seg_h * (i + 0.5)
        cz = z - 0.028 * i
        w0 = widths[i]
        w1 = widths[i + 1] if i + 1 < len(widths) else widths[-1]
        b.taper_box("cape", cfg["cape"], (0.0, cy, cz), seg_h + 0.004, (w0, depth), (w1, depth))
    b.box("cape", cfg["cape_trim"], (0.0, 0.100, z - 0.084), (0.336, 0.020, 0.020))
    b.box("cape", cfg["cape_trim"], (0.0, 0.742, z + 0.004), (0.215, 0.018, 0.018))


# ---------------------------------------------------------------------------
# warrior
# ---------------------------------------------------------------------------

def build_warrior():
    cfg = {
        "skin": "skin",
        "torso": "steel",
        "chest": "steel_light",
        "belt": "leather",
        "accent": "crimson",
        "pauldron": "steel_dark",
        "sleeve": "steel",
        "glove": "leather",
        "leg_armor": "steel_dark",
        "knee": "steel_light",
        "boot": "leather",
        "cape": "crimson",
        "cape_trim": "gold",
    }
    b = Builder(MATS)
    add_body(b, cfg)

    # helmet
    b.frustum("head", "steel", (0.0, 0.888, 0.0), 0.097, 0.086, 0.075, 10)
    b.frustum("head", "steel_light", (0.0, 0.934, -0.004), 0.086, 0.030, 0.060, 10)
    b.box("head", "steel_dark", (0.0, 0.875, 0.083), (0.115, 0.018, 0.020))
    b.box("head", "steel_light", (0.0, 0.878, 0.089), (0.020, 0.105, 0.026))
    for sx in (1.0, -1.0):
        b.box("head", "steel_dark", (sx * 0.085, 0.852, 0.030), (0.026, 0.080, 0.095))
        b.box("head", "gold", (sx * 0.095, 0.900, -0.010), (0.018, 0.020, 0.050))
    # plume crest
    for i in range(5):
        t = i / 4.0
        cy = 0.982 - 0.055 * t
        cz = 0.010 - 0.115 * t
        b.taper_box("head", "crimson" if i % 2 == 0 else "crimson_light",
                    (0.0, cy, cz), 0.070, (0.026, 0.035), (0.018, 0.026),
                    rot=(0.42, 0.0, 0.0))
    b.box("head", "gold", (0.0, 0.962, 0.012), (0.040, 0.020, 0.050))
    b.box("head", "crimson_dark", (0.0, 0.940, -0.045), (0.048, 0.020, 0.045))

    # pauldrons + spikes
    for sx in (1.0, -1.0):
        b.taper_box("arm_l" if sx > 0 else "arm_r", "steel_light",
                    (sx * 0.196, 0.770, 0.0), 0.052, (0.078, 0.086), (0.060, 0.070))
        b.cylinder_between("arm_l" if sx > 0 else "arm_r", "steel_white",
                           (sx * 0.230, 0.790, 0.0), (sx * 0.286, 0.856, -0.010),
                           0.020, 0.0, 6)
        b.cylinder_between("arm_l" if sx > 0 else "arm_r", "gold",
                           (sx * 0.224, 0.784, 0.0), (sx * 0.236, 0.798, -0.002),
                           0.024, 0.022, 6)
        b.box("arm_l" if sx > 0 else "arm_r", "gold",
              (sx * 0.190, 0.700, 0.068), (0.075, 0.014, 0.014))
        b.box("leg_l" if sx > 0 else "leg_r", "steel_light",
              (sx * 0.078, 0.360, 0.052), (0.070, 0.040, 0.020))

    # greatsword (attached to right hand)
    b.box("weapon", "leather", (-0.190, 0.405, 0.020), (0.044, 0.090, 0.048))
    b.box("weapon", "gold", (-0.190, 0.452, 0.020), (0.180, 0.030, 0.038))
    b.taper_box("weapon", "steel_white", (-0.190, 0.720, 0.020), 0.500,
                (0.034, 0.011), (0.012, 0.006))
    b.box("weapon", "steel", (-0.190, 0.720, 0.027), (0.014, 0.455, 0.004))
    b.octahedron("weapon", "crimson_light", (-0.190, 0.358, 0.020), 0.034)
    b.box("weapon", "gold", (-0.190, 0.505, 0.020), (0.090, 0.014, 0.026))

    # round shield (attached to left hand)
    b.frustum("offhand", "crimson", (0.204, 0.438, 0.098), 0.140, 0.140, 0.022, 14,
              rot=(math.pi * 0.5, 0.0, 0.0))
    b.annulus("offhand", "gold", (0.204, 0.438, 0.100), 0.116, 0.144, 0.028, 14,
              rot=(math.pi * 0.5, 0.0, 0.0))
    b.sphere("offhand", "steel_light", (0.204, 0.438, 0.116), 0.047, 8, 4, (1.0, 1.0, 0.55))
    b.box("offhand", "gold", (0.204, 0.438, 0.100), (0.032, 0.140, 0.020))
    b.octahedron("offhand", "crimson_dark", (0.204, 0.438, 0.060), 0.030)
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        b.box("offhand", "gold_light",
              (0.204 + 0.130 * math.sin(a), 0.438 + 0.130 * math.cos(a), 0.114),
              (0.018, 0.018, 0.012))

    return b


# ---------------------------------------------------------------------------
# archmage
# ---------------------------------------------------------------------------

def build_archmage():
    cfg = {
        "skin": "skin",
        "torso": "navy",
        "chest": "navy_light",
        "belt": "gold",
        "accent": "gold",
        "pauldron": "navy_deep",
        "sleeve": "navy_light",
        "glove": "skin",
        "leg_armor": "navy_deep",
        "knee": "navy_deep",
        "boot": "navy_deep",
        "cape": "navy_deep",
        "cape_trim": "gold",
    }
    b = Builder(MATS)
    add_body(b, cfg, hide_legs=True)

    # robe skirt over the legs
    b.frustum("hips", "navy", (0.0, 0.290, 0.0), 0.205, 0.100, 0.420, 12)
    b.annulus("hips", "gold", (0.0, 0.086, 0.0), 0.198, 0.208, 0.026, 12)
    b.annulus("hips", "navy_light", (0.0, 0.150, 0.0), 0.186, 0.194, 0.018, 12)
    b.taper_box("hips", "navy_light", (0.0, 0.300, 0.135), 0.400,
                (0.062, 0.014), (0.028, 0.012))
    b.box("hips", "gold", (0.0, 0.300, 0.145), (0.014, 0.300, 0.006))

    # chest star + collar
    b.octahedron("torso", "gold_light", (0.0, 0.650, 0.094), 0.042, (1.0, 1.4, 0.35))
    b.box("torso", "gold", (0.0, 0.745, 0.080), (0.120, 0.020, 0.020))
    b.frustum("torso", "navy_deep", (0.0, 0.762, 0.0), 0.062, 0.052, 0.050, 10)

    # beard + moustache + brows
    b.taper_box("head", "beard_white", (0.0, 0.770, 0.072), 0.200,
                (0.070, 0.030), (0.046, 0.020), rot=(-0.06, 0.0, 0.0))
    b.box("head", "beard_white", (0.030, 0.812, 0.092), (0.052, 0.014, 0.020), rot=(0.0, 0.0, 0.35))
    b.box("head", "beard_white", (-0.030, 0.812, 0.092), (0.052, 0.014, 0.020), rot=(0.0, 0.0, -0.35))
    b.box("head", "beard_white", (0.033, 0.889, 0.088), (0.036, 0.011, 0.012))
    b.box("head", "beard_white", (-0.033, 0.889, 0.088), (0.036, 0.011, 0.012))

    # pointed hat
    b.frustum("head", "navy_deep", (0.0, 0.934, 0.0), 0.160, 0.160, 0.022, 14)
    b.frustum("head", "navy", (0.0, 1.010, 0.0), 0.137, 0.048, 0.150, 12)
    b.frustum("head", "navy_light", (0.0, 1.125, -0.012), 0.048, 0.010, 0.100, 8,
              rot=(-0.16, 0.0, 0.0))
    b.octahedron("head", "gold_light", (0.0, 1.180, -0.030), 0.022)
    b.annulus("head", "gold", (0.0, 0.952, 0.0), 0.140, 0.154, 0.022, 14)
    b.octahedron("head", "gold_light", (0.0, 0.950, 0.150), 0.026, (1.0, 1.2, 0.4))

    # wide sleeves, belt sash
    for sx in (1.0, -1.0):
        b.frustum("arm_l" if sx > 0 else "arm_r", "navy",
                  (sx * 0.196, 0.650, 0.0), 0.070, 0.092, 0.200, 9,
                  rot=(0.0, 0.0, -sx * 0.10))
        b.annulus("arm_l" if sx > 0 else "arm_r", "gold",
                  (sx * 0.202, 0.548, 0.0), 0.058, 0.074, 0.022, 9)
    b.box("torso", "gold", (0.0, 0.560, 0.0), (0.208, 0.036, 0.160))

    # staff with elemental orb
    b.cylinder_between("weapon", "wood", (-0.190, 0.020, 0.060), (-0.190, 1.005, 0.060),
                       0.021, 0.016, 6)
    b.annulus("weapon", "gold", (-0.190, 0.440, 0.060), 0.024, 0.036, 0.024, 8)
    b.annulus("weapon", "gold", (-0.190, 0.800, 0.060), 0.022, 0.034, 0.022, 8)
    b.annulus("weapon", "gold", (-0.190, 1.010, 0.060), 0.050, 0.064, 0.020, 12)
    for i in range(3):
        a = 2.0 * math.pi * i / 3.0 + 0.4
        x = -0.190 + 0.052 * math.sin(a)
        z = 0.060 + 0.052 * math.cos(a)
        b.cylinder_between("weapon", "gold", (x, 1.010, z),
                           (-0.190 + 0.030 * math.sin(a), 1.075, 0.060 + 0.030 * math.cos(a)),
                           0.010, 0.006, 5)
    b.box("head", "glow_blue", (0.031, 0.861, 0.090), (0.013, 0.012, 0.006))
    b.box("head", "glow_blue", (-0.031, 0.861, 0.090), (0.013, 0.012, 0.006))
    b.sphere("weapon", "fire", (-0.190, 1.070, 0.060), 0.055, 10, 5)
    b.sphere("weapon", "flame", (-0.190, 1.075, 0.060), 0.031, 8, 4)

    # floating elemental shards orbit the focus joint
    for i, mat in enumerate(("fire", "glow_cyan", "flame")):
        a = 2.0 * math.pi * i / 3.0
        b.octahedron("focus", mat,
                     (0.235 * math.sin(a), 0.945 + 0.045 * (i % 2), 0.235 * math.cos(a)),
                     0.026, (1.0, 1.3, 1.0))
    return b


# ---------------------------------------------------------------------------
# chronomancer
# ---------------------------------------------------------------------------

def build_chronomancer():
    cfg = {
        "skin": "skin",
        "torso": "violet",
        "chest": "violet_light",
        "belt": "gold",
        "accent": "cyan",
        "pauldron": "violet_dark",
        "sleeve": "violet_light",
        "glove": "skin",
        "leg_armor": "violet_dark",
        "knee": "violet_dark",
        "boot": "violet_dark",
        "cape": "violet_dark",
        "cape_trim": "gold",
    }
    b = Builder(MATS)
    add_body(b, cfg, hide_legs=True)

    # layered skirt
    b.frustum("hips", "violet_dark", (0.0, 0.285, 0.0), 0.212, 0.098, 0.420, 12)
    b.frustum("hips", "violet", (0.0, 0.235, -0.010), 0.198, 0.120, 0.300, 12)
    b.annulus("hips", "cyan", (0.0, 0.082, 0.0), 0.204, 0.214, 0.026, 12)
    b.annulus("hips", "gold", (0.0, 0.145, 0.0), 0.190, 0.198, 0.018, 12)
    b.taper_box("hips", "violet_light", (0.0, 0.320, 0.130), 0.380,
                (0.058, 0.014), (0.026, 0.010))
    b.box("hips", "cyan", (0.0, 0.320, 0.140), (0.012, 0.270, 0.006))

    # clock face on the chest
    b.annulus("torso", "gold", (0.0, 0.645, 0.096), 0.040, 0.052, 0.016, 12,
              rot=(math.pi * 0.5, 0.0, 0.0))
    b.box("torso", "glow_cyan", (0.0, 0.645, 0.104), (0.006, 0.038, 0.006))
    b.box("torso", "glow_cyan", (0.0, 0.645, 0.104), (0.032, 0.005, 0.006))
    b.octahedron("torso", "cyan", (0.0, 0.645, 0.108), 0.010)

    # hood / cowl
    b.frustum("head", "violet_dark", (0.0, 0.905, -0.028), 0.125, 0.015, 0.190, 10,
              rot=(-0.12, 0.0, 0.0))
    b.box("head", "violet_dark", (0.0, 0.858, -0.020), (0.200, 0.160, 0.040))
    b.annulus("head", "violet", (0.0, 0.790, 0.0), 0.085, 0.132, 0.050, 10)
    b.box("head", "violet_light", (0.0, 0.940, -0.058), (0.050, 0.070, 0.030), rot=(0.2, 0.0, 0.0))
    b.octahedron("head", "glow_cyan", (0.0, 0.995, -0.045), 0.018)
    b.box("head", "glow_cyan", (0.031, 0.861, 0.088), (0.016, 0.012, 0.010))
    b.box("head", "glow_cyan", (-0.031, 0.861, 0.088), (0.016, 0.012, 0.010))
    b.box("head", "silver", (0.070, 0.840, 0.030), (0.016, 0.070, 0.030))
    b.box("head", "silver", (-0.070, 0.840, 0.030), (0.016, 0.070, 0.030))

    # clockwork pauldron on the left arm
    b.annulus("arm_l", "bronze", (0.262, 0.755, 0.0), 0.042, 0.064, 0.024, 10,
              rot=(0.0, 0.0, math.pi * 0.5))
    b.annulus("arm_l", "gold", (0.262, 0.755, 0.0), 0.020, 0.030, 0.028, 8,
              rot=(0.0, 0.0, math.pi * 0.5))
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        b.box("arm_l", "bronze",
              (0.262, 0.755 + 0.078 * math.sin(a), 0.078 * math.cos(a)),
              (0.020, 0.022, 0.022))
    b.box("arm_l", "cyan", (0.262, 0.820, 0.0), (0.026, 0.018, 0.018))
    b.annulus("arm_r", "bronze", (-0.196, 0.720, 0.0), 0.036, 0.050, 0.020, 8,
              rot=(0.0, 0.0, math.pi * 0.5))

    # staff + hourglass
    b.cylinder_between("weapon", "iron", (-0.190, 0.020, 0.060), (-0.190, 0.930, 0.060),
                       0.018, 0.014, 6)
    b.annulus("weapon", "gold", (-0.190, 0.430, 0.060), 0.022, 0.034, 0.022, 8)
    b.annulus("weapon", "gold", (-0.190, 0.760, 0.060), 0.020, 0.032, 0.020, 8)
    # frame
    b.annulus("weapon", "gold", (-0.190, 0.930, 0.060), 0.038, 0.052, 0.020, 10)
    b.annulus("weapon", "gold", (-0.190, 1.105, 0.060), 0.038, 0.052, 0.020, 10)
    for i in range(4):
        a = 2.0 * math.pi * i / 4.0 + 0.2
        x = -0.190 + 0.042 * math.sin(a)
        z = 0.060 + 0.042 * math.cos(a)
        b.cylinder_between("weapon", "gold", (x, 0.930, z), (x, 1.105, z), 0.008, 0.008, 4)
    b.frustum("weapon", "glow_cyan", (-0.190, 0.982, 0.060), 0.004, 0.042, 0.070, 8)
    b.frustum("weapon", "glow_cyan", (-0.190, 1.052, 0.060), 0.042, 0.004, 0.070, 8)
    b.octahedron("weapon", "flame", (-0.190, 1.018, 0.060), 0.024)
    b.octahedron("weapon", "cyan", (-0.190, 1.018, 0.060), 0.013)

    # spinning rings around the hourglass
    b.annulus("focus", "glow_cyan", (-0.190, 1.018, 0.060), 0.082, 0.092, 0.012, 12,
              rot=(0.30, 0.0, 0.0))
    b.annulus("focus", "gold", (-0.190, 1.018, 0.060), 0.100, 0.108, 0.010, 12,
              rot=(-0.35, 0.0, 0.55))
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        b.box("focus", "glow_cyan",
              (-0.190 + 0.118 * math.sin(a), 1.018 + 0.045 * math.cos(a), 0.060 + 0.060 * math.sin(a * 2)),
              (0.016, 0.016, 0.016))

    # temporal aura rings
    b.annulus("aura", "glow_cyan", (0.0, 0.600, 0.0), 0.300, 0.312, 0.012, 16,
              rot=(0.12, 0.0, 0.10))
    b.annulus("aura", "cyan", (0.0, 0.690, 0.0), 0.240, 0.248, 0.010, 16,
              rot=(-0.10, 0.0, -0.16))
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        b.octahedron("aura", "glow_blue",
                     (0.335 * math.sin(a), 0.600, 0.335 * math.cos(a)), 0.016, (1.0, 1.6, 1.0))
    return b


# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------

def _fmt(x):
    return "{:.5f}".format(x).rstrip("0").rstrip(".") if abs(x) > 1e-8 else "0"


def _material_name(color):
    r, g, bb = MATS[color][0]
    return "m_{:02x}{:02x}{:02x}".format(r, g, bb)


def write_character(out_dir, name, builder, joints, joint_world):
    os.makedirs(out_dir, exist_ok=True)
    obj_path = os.path.join(out_dir, name + ".obj")
    mtl_path = os.path.join(out_dir, name + ".mtl")
    rig_path = os.path.join(out_dir, name + ".rig.json")

    verts = []
    vert_index = {}
    groups = OrderedDict()
    used_mats = OrderedDict()

    def vidx(p):
        key = tuple(round(c, 5) for c in p)
        if key not in vert_index:
            vert_index[key] = len(verts) + 1
            verts.append(p)
        return vert_index[key]

    for joint, _, _ in joints:
        tris = builder.tris.get(joint, [])
        if not tris:
            continue
        packed = []
        for color, p0, p1, p2 in tris:
            used_mats[color] = MATS[color]
            packed.append((color, vidx(p0), vidx(p1), vidx(p2)))
        groups[joint] = packed

    with open(obj_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# VX procedural hero model: " + name + "\n")
        f.write("# Generated by tools/characters.py - flat-shaded, Y up, faces +Z\n")
        f.write("mtllib " + name + ".mtl\n")
        for p in verts:
            f.write("v {0} {1} {2}\n".format(_fmt(p[0]), _fmt(p[1]), _fmt(p[2])))
        for joint, tris in groups.items():
            f.write("\no {}\n".format(joint))
            current = None
            for color, a, b_, c in tris:
                if color != current:
                    f.write("usemtl {}\n".format(_material_name(color)))
                    current = color
                f.write("f {} {} {}\n".format(a, b_, c))

    with open(mtl_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# VX material palette\n")
        for color, (rgb, emissive) in used_mats.items():
            r, g, bb = rgb
            f.write("newmtl {}\n".format(_material_name(color)))
            f.write("Kd {:.5f} {:.5f} {:.5f}\n".format(r / 255.0, g / 255.0, bb / 255.0))
            if emissive:
                f.write("Ke {:.5f} {:.5f} {:.5f}\n".format(r / 255.0, g / 255.0, bb / 255.0))
            f.write("illum 1\n\n")

    rig = {
        "name": name,
        "height": 1.0,
        "up_axis": "Y",
        "forward_axis": "+Z",
        "joints": [
            {"name": j, "parent": p, "rest": [round(v, 5) for v in r],
             "world": [round(v, 5) for v in joint_world[j]]}
            for j, p, r in joints
        ],
        "parts": list(groups.keys()),
    }
    with open(rig_path, "w", encoding="utf-8") as f:
        json.dump(rig, f, indent=2)
        f.write("\n")
    return obj_path, len(verts), sum(len(v) for v in groups.values())


CHARACTERS = {
    "warrior": (build_warrior, BASE_JOINTS),
    "archmage": (build_archmage, joints_with([("focus", "root", (0.0, 0.900, 0.0))])),
    "chronomancer": (build_chronomancer,
                     joints_with([("focus", "weapon", (0.0, 0.590, 0.040)),
                                  ("aura", "root", (0.0, 0.600, 0.0))])),
}


def generate_all(out_dir):
    summary = []
    for name, (fn, joints) in CHARACTERS.items():
        b = fn()
        jw = compute_joint_world(joints)
        obj_path, nv, nf = write_character(out_dir, name, b, joints, jw)
        summary.append((name, obj_path, nv, nf, b.bounds_min, b.bounds_max))
    return summary


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "assets", "models")
    for row in generate_all(out):
        print(row[0], "verts=", row[2], "tris=", row[3],
              "min=", tuple(round(v, 3) for v in row[4]),
              "max=", tuple(round(v, 3) for v in row[5]))