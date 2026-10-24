#!/usr/bin/env python3
"""Generates the text-free Universal App Store creative (5244 x 2950, 16:9).

Concept C: a twilight landscape in the style of the in-app Scenes. A path of
blue "step" lights leads a walker toward the app's unlock/hourglass mark rising
over the horizon: movement earns the time. No copy, so one asset serves every
locale. Focal mark sits in Apple's art safe area (centered, above the middle).

Usage: python3 generate.py  -> writes universal.svg, then render.sh makes PNG.
"""
import math
import random
from pathlib import Path

W, H = 5244, 2950
CX = W / 2
HZ = 1640  # horizon line
rnd = random.Random(7)

NAVY = "#0A1A3F"
CREAM = "#F5F0E6"
BLUE = "#2F6BFF"

out = []
add = out.append


def f(v):
    return f"{v:.1f}"


# ---------- defs ----------
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
add("""<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1640" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#030819"/>
    <stop offset=".42" stop-color="#0A1640"/>
    <stop offset=".68" stop-color="#1A2258"/>
    <stop offset=".86" stop-color="#43306A"/>
    <stop offset="1" stop-color="#8E5276"/>
  </linearGradient>
  <radialGradient id="glow" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(2622 1010) scale(1500 1150)">
    <stop offset="0" stop-color="#4C7BFF" stop-opacity=".6"/>
    <stop offset=".35" stop-color="#3559D8" stop-opacity=".22"/>
    <stop offset="1" stop-color="#1A2258" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="halo" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(2622 1010) scale(640)">
    <stop offset="0" stop-color="#F5F0E6" stop-opacity=".22"/>
    <stop offset=".6" stop-color="#9DB6FF" stop-opacity=".08"/>
    <stop offset="1" stop-color="#9DB6FF" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#0E2B2C"/>
    <stop offset=".25" stop-color="#0F3324"/>
    <stop offset="1" stop-color="#071A12"/>
  </linearGradient>
  <linearGradient id="path" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#7C93C9" stop-opacity=".35"/>
    <stop offset=".5" stop-color="#5E7A8C" stop-opacity=".45"/>
    <stop offset="1" stop-color="#3D5560" stop-opacity=".55"/>
  </linearGradient>
  <linearGradient id="hillL" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#0A2416"/>
    <stop offset="1" stop-color="#13452A"/>
  </linearGradient>
  <linearGradient id="hillR" x1="1" y1="0" x2="0" y2="0">
    <stop offset="0" stop-color="#0A2416"/>
    <stop offset="1" stop-color="#13452A"/>
  </linearGradient>
  <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#040A14" stop-opacity="0"/>
    <stop offset="1" stop-color="#040A14" stop-opacity=".85"/>
  </linearGradient>
  <radialGradient id="vignette" cx=".5" cy=".42" r=".75">
    <stop offset=".55" stop-color="#000" stop-opacity="0"/>
    <stop offset="1" stop-color="#000" stop-opacity=".55"/>
  </radialGradient>
  <filter id="blur40" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter>
  <filter id="blur14" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="14"/></filter>
  <filter id="blur6" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="6"/></filter>
  <filter id="grain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="3" stitchTiles="stitch"/>
    <feColorMatrix values="0 0 0 0 .5  0 0 0 0 .5  0 0 0 0 .5  0 0 0 .06 0"/>
  </filter>
</defs>""")

# ---------- sky ----------
add(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
add(f'<rect width="{W}" height="{HZ + 40}" fill="url(#glow)"/>')

# stars, sparser near the glow
for _ in range(320):
    x, y = rnd.uniform(0, W), rnd.uniform(0, HZ - 260)
    if math.hypot((x - CX) / 1.4, y - 1010) < 760:
        continue
    r = rnd.choice([2, 2, 3, 3, 4, 5])
    add(f'<circle cx="{f(x)}" cy="{f(y)}" r="{r}" fill="#DCE4FF" opacity="{rnd.uniform(.15, .7):.2f}"/>')

# ---------- distant ridge + city lights ----------
pts = []
for i in range(0, W + 60, 60):
    y = HZ - 60 + 38 * math.sin(i / 410) + 26 * math.sin(i / 157 + 1.3) + rnd.uniform(-6, 6)
    pts.append(f"{i},{f(y)}")
add(f'<polygon points="0,{H} {" ".join(pts)} {W},{H}" fill="#1E2150" opacity=".9"/>')
add(f'<rect x="0" y="{HZ - 10}" width="{W}" height="{H}" fill="#101A38"/>')
for _ in range(700):
    x = rnd.uniform(0, W)
    y = HZ + rnd.uniform(-4, 70) * rnd.random()
    add(f'<circle cx="{f(x)}" cy="{f(y)}" r="{rnd.choice([2, 3, 3, 4])}" fill="#FFD48A" opacity="{rnd.uniform(.25, .85):.2f}"/>')

# ---------- meadow ----------
pts = []
for i in range(0, W + 60, 60):
    y = HZ + 70 + 22 * math.sin(i / 520 + .4)
    pts.append(f"{i},{f(y)}")
add(f'<polygon points="0,{H} {" ".join(pts)} {W},{H}" fill="url(#ground)"/>')

add(f'<ellipse cx="{CX}" cy="{HZ + 60}" rx="1300" ry="150" fill="#4C7BFF" opacity=".22" filter="url(#blur40)"/>')

# ---------- path of earned steps ----------
def path_at(t):
    """Centerline and half-width of the path, t=0 at horizon, 1 at bottom."""
    y = HZ + 80 + (H + 120 - HZ - 80) * t ** 1.7
    x = CX + 330 * math.sin(t * math.pi * 1.25) * t ** .9 - 120 * t
    hw = 6 + 520 * t ** 1.9
    return x, y, hw

left, right = [], []
for k in range(0, 121):
    t = k / 120
    x, y, hw = path_at(t)
    left.append(f"{f(x - hw)},{f(y)}")
    right.append(f"{f(x + hw)},{f(y)}")
add(f'<polygon points="{" ".join(left + right[::-1])}" fill="url(#path)"/>')

# step lights along the path, glowing toward the mark
steps = [i / 26 for i in range(1, 26)]
for t in steps:
    x, y, hw = path_at(t)
    r = 5 + 30 * t ** 1.4
    add(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r * 2.6)}" fill="{BLUE}" opacity=".55" filter="url(#blur14)"/>')
    add(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="#8FB0FF"/>')

# ---------- walker (back view, blue sweater like the in-app scenes) ----------
wx, wy, _ = path_at(.45)
s = .62
add(f'<g transform="translate({f(wx)} {f(wy)}) scale({s})">')
add('<ellipse cx="0" cy="4" rx="70" ry="14" fill="#000" opacity=".35"/>')
add('<path d="M -34 -150 L -44 -8 Q -44 2 -32 2 L -20 2 L -12 -150 Z" fill="#141A2A"/>')
add('<path d="M 12 -150 L 26 -20 Q 28 -6 40 -6 L 50 -6 L 34 -150 Z" fill="#10141F"/>')
add('<rect x="-48" y="-14" width="34" height="14" rx="7" fill="#C9CED8"/>')
add('<rect x="24" y="-18" width="32" height="14" rx="7" fill="#C9CED8"/>')
add('<path d="M -58 -300 Q -60 -330 -30 -336 L 30 -336 Q 60 -330 58 -300 L 54 -140 Q 0 -128 -54 -140 Z" fill="#2E4BD8"/>')
add('<path d="M 0 -336 L 30 -336 Q 60 -330 58 -300 L 54 -140 Q 28 -134 0 -133 Z" fill="#2440B8" opacity=".75"/>')
add('<path d="M -56 -318 Q -82 -250 -76 -168 Q -66 -160 -58 -170 L -48 -290 Z" fill="#2A45C8"/>')
add('<path d="M 56 -318 Q 82 -250 80 -170 Q 70 -162 62 -172 L 48 -290 Z" fill="#203AA8"/>')
add('<circle cx="-70" cy="-162" r="10" fill="#C69A7E"/>')
add('<rect x="-12" y="-354" width="24" height="22" fill="#B98B70"/>')
add('<ellipse cx="0" cy="-386" rx="34" ry="40" fill="#15100E"/>')
add('</g>')

# ---------- side hills + topiary trees ----------
def hill(points, fill):
    add(f'<path d="{points}" fill="{fill}"/>')

hill(f"M 0 {HZ - 120} C 500 {HZ - 160}, 1100 {HZ + 40}, 1700 {HZ + 330} C 2000 {HZ + 520}, 2050 {H - 300}, 1900 {H} L 0 {H} Z", "url(#hillL)")
hill(f"M {W} {HZ - 160} C {W - 520} {HZ - 190}, {W - 1100} {HZ + 20}, {W - 1650} {HZ + 300} C {W - 1980} {HZ + 480}, {W - 2000} {H - 320}, {W - 1820} {H} L {W} {H} Z", "url(#hillR)")


def tree(cx, cy, size, toward_center):
    """Rounded topiary clump; lit on the side facing the glowing mark."""
    lit = "#1A5C37" if toward_center else "#154C2D"
    gid = f"t{rnd.randrange(10**9)}"
    fx = ".72" if cx < CX else ".28"
    add(f'<radialGradient id="{gid}" cx=".5" cy=".5" r=".6" fx="{fx}" fy=".35"><stop offset="0" stop-color="{lit}"/><stop offset="1" stop-color="#061810"/></radialGradient>')
    blobs = [(0, 0, .85)] + [(rnd.uniform(-.8, .8), rnd.uniform(-.95, .45), rnd.uniform(.32, .6)) for _ in range(11)]
    side = 1 if cx < CX else -1
    for dx, dy, rr in sorted(blobs, key=lambda b: b[1]):
        bx, by, br = cx + dx * size, cy + dy * size, rr * size
        add(f'<circle cx="{f(bx)}" cy="{f(by)}" r="{f(br)}" fill="url(#{gid})"/>')
        add(f'<circle cx="{f(bx + side * br * .18)}" cy="{f(by - br * .12)}" r="{f(br * .86)}" fill="none" stroke="#3D8F5C" stroke-opacity=".10" stroke-width="{f(br * .08)}"/>')


for cx, cy, size in [(-80, 380, 620), (380, 900, 430), (120, 1500, 360), (900, 1560, 230), (1350, 1820, 160)]:
    tree(cx, cy, size, True)
for cx, cy, size in [(W + 60, 520, 580), (W - 420, 1080, 380), (W - 140, 1560, 340), (W - 950, 1600, 210), (W - 1380, 1830, 150)]:
    tree(cx, cy, size, True)

# blue meadow flowers near the bottom, like the earn-path scene
for _ in range(900):
    x = rnd.uniform(0, W)
    y = rnd.uniform(HZ + 420, H)
    px, _, phw = path_at(min(1, ((y - HZ - 80) / (H + 120 - HZ - 80)) ** (1 / 1.7)))
    if abs(x - px) < phw + 20:
        continue
    r = 2 + 7 * (y - HZ) / (H - HZ)
    add(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="#5D7BFF" opacity="{rnd.uniform(.25, .7):.2f}"/>')

# ---------- the mark: unlocked padlock with hourglass, rising over the horizon ----------
add(f'<circle cx="{CX}" cy="1010" r="640" fill="url(#halo)"/>')
ms, my = 1.15, 1052
add(f'<g transform="translate({CX} {my}) scale({ms})">')
# soft bloom behind the mark
add(f'<rect x="-270" y="-50" width="540" height="420" rx="96" fill="#9DB6FF" opacity=".35" filter="url(#blur40)"/>')
add(f'<path d="M -170 -20 L -170 -250 A 170 170 0 0 1 170 -250 L 170 -175" fill="none" stroke="{CREAM}" stroke-width="84" stroke-linecap="round"/>')
add(f'<rect x="-262" y="-44" width="524" height="408" rx="92" fill="{CREAM}"/>')
add(f'<rect x="-128" y="14" width="256" height="34" rx="17" fill="{NAVY}"/>')
add(f'<rect x="-128" y="292" width="256" height="34" rx="17" fill="{NAVY}"/>')
add(f'<path d="M -104 44 L 104 44 C 104 118, 26 142, 16 168 C 26 196, 104 222, 104 296 L -104 296 C -104 222, -26 196, -16 168 C -26 142, -104 118, -104 44 Z" fill="{NAVY}"/>')
add(f'<path d="M -92 294 C -86 252, -42 226, 0 222 C 42 226, 86 252, 92 294 Z" fill="{BLUE}" filter="url(#blur6)" opacity=".8"/>')
add(f'<path d="M -92 294 C -86 252, -42 226, 0 222 C 42 226, 86 252, 92 294 Z" fill="{BLUE}"/>')
add(f'<rect x="-4" y="170" width="8" height="56" rx="4" fill="{BLUE}"/>')
add('</g>')

# ---------- finishing ----------
add(f'<rect y="{H - 900}" width="{W}" height="900" fill="url(#fade)"/>')
add(f'<rect width="{W}" height="{H}" fill="url(#vignette)"/>')
add(f'<rect width="{W}" height="{H}" filter="url(#grain)"/>')
add("</svg>")

dest = Path(__file__).with_name("universal.svg")
dest.write_text("\n".join(out))
print(f"wrote {dest}")
