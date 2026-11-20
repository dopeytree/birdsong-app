#!/usr/bin/env python3
"""Draw the plate's icons (lib/ui/plate_icons.dart) as an SVG, to look at
them outside the app: each at the size the app uses and large, on the
plate's paper, plus the source pill and the buttons as they sit together.

    python3 tool/icon_preview.py out.svg
"""
import math, re, sys
from pathlib import Path

src = (Path(__file__).resolve().parent.parent / 'lib/ui/plate_icons.dart').read_text()
consts = dict(re.findall(r'(\w+) = ([\d.]+)', src.split('const plateGlyphs')[0].split('const double')[1]))
STROKE, FINE, HATCHW, GAP, DOT = (float(consts[k]) for k in
                                  ('strokeWeight', 'fineWeight', 'hatchWeight', 'hatchGap', 'dotGap'))
body = src.split('const plateGlyphs')[1].split('};')[0]
glyphs = {}
for name, marks in re.findall(r'PlateGlyph\.(\w+): \[(.*?)\n  \],', body, re.S):
    out = []
    for ink, parts, angle in re.findall(r"Mark\(Ink\.(\w+),\s*((?:'[^']*'\s*)+)(?:, angle: ([-\d.]+))?\)", marks):
        d = ''.join(re.findall(r"'([^']*)'", parts))
        out.append((ink, d, float(angle or 45)))
    glyphs[name] = out

PAPER, INK, SEPIA, MADDER, RULE = '#eee5ce', '#2a241c', '#6b5338', '#8c3b2a', '#bcab86'
uid = [0]

def glyph(name, x, y, size, color):
    k = size / 24
    out = [f'<g transform="translate({x} {y}) scale({k})">']
    for ink, d, angle in glyphs[name]:
        if ink in ('stroke', 'fine'):
            w = STROKE if ink == 'stroke' else FINE
            out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" '
                       'stroke-linecap="round" stroke-linejoin="round"/>')
        elif ink == 'fill':
            out.append(f'<path d="{d}" fill="{color}"/>')
        elif ink == 'dots':
            out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{STROKE}" '
                       f'stroke-linecap="round" stroke-dasharray="0 {DOT}"/>')
        elif ink == 'hatch':
            uid[0] += 1
            cid = f'c{uid[0]}'
            a = math.radians(angle)
            dx, dy = math.cos(a), math.sin(a)
            lines = []
            t = -24.0
            while t <= 24:
                ox, oy = 12 - dy * t, 12 + dx * t
                lines.append(f'M{ox - dx * 30:.2f} {oy - dy * 30:.2f}L{ox + dx * 30:.2f} {oy + dy * 30:.2f}')
                t += GAP
            out.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>'
                       f'<path clip-path="url(#{cid})" d="{"".join(lines)}" stroke="{color}" '
                       f'stroke-width="{HATCHW}" stroke-linecap="round"/>')
    out.append('</g>')
    return ''.join(out)

names = list(glyphs)
W = 40 + 120 * 7
rows = math.ceil(len(names) / 7)
H = 120 + rows * 150 + 200
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
       f'<rect width="100%" height="100%" fill="{PAPER}"/>',
       f'<text x="20" y="34" font-family="IM Fell English, Georgia, serif" font-size="22" fill="{INK}">'
       'The plate\'s icons</text>']
for i, name in enumerate(names):
    cx, cy = 20 + (i % 7) * 120, 60 + (i // 7) * 150
    svg.append(glyph(name, cx + 12, cy, 96, MADDER if name in ('record', 'stop') else INK))
    svg.append(glyph(name, cx + 30, cy + 102, 22, MADDER))
    svg.append(glyph(name, cx + 64, cy + 102, 22, SEPIA))
    svg.append(f'<text x="{cx + 60}" y="{cy + 142}" text-anchor="middle" font-family="Georgia, serif" '
               f'font-style="italic" font-size="13" fill="{SEPIA}">{name}</text>')
# the buttons together, as over the plate
y = 60 + rows * 150 + 30
svg.append(f'<text x="20" y="{y}" font-family="Georgia, serif" font-style="italic" font-size="14" '
           f'fill="{SEPIA}">As over the plate (record, pill, menu, and the view under it)</text>')
x0, y0 = 40, y + 24
svg.append(glyph('record', x0 + 4, y0 + 8, 18 * 1.25, MADDER))
px = x0 + 44
svg.append(f'<rect x="{px}" y="{y0 + 5}" width="92" height="36" rx="18" fill="{PAPER}" stroke="{MADDER}" '
           'stroke-opacity=".55"/>')
svg.append(f'<path d="M{px + 18} {y0 + 5.5}H{px + 46}V{y0 + 40.5}H{px + 18}A17.5 17.5 0 0 1 {px + 18} {y0 + 5.5}Z" '
           f'fill="{MADDER}"/>')
svg.append(glyph('listen', px + 12.5, y0 + 12.5, 21, PAPER))
svg.append(glyph('station', px + 58.5, y0 + 12.5, 21, SEPIA))
svg.append(glyph('menu', px + 104, y0 + 12, 24, MADDER))
svg.append(glyph('plate', px + 104, y0 + 60, 24, MADDER))
svg.append(glyph('map', x0 + 8, y0 + 130, 22, MADDER))
svg.append(glyph('share', x0 + 230, y0 + 130, 22, MADDER))
svg.append(f'<text x="{x0 + 40}" y="{y0 + 146}" font-family="Georgia, serif" font-style="italic" '
           f'font-size="12" fill="{SEPIA}">map, bottom left · share, bottom right</text>')
svg.append('</svg>')
Path(sys.argv[1] if len(sys.argv) > 1 else 'icons.svg').write_text(''.join(svg))
