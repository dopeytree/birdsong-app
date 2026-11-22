#!/usr/bin/env python3
"""Pull the named woods and heaths out of OS Open Names for the app.

    python3 -I tool/os_woods.py <unzipped opname_csv_gb folder>

Reads Data/*.csv (OS Open Names, Ordnance Survey, Open Government Licence:
"Contains OS data (c) Crown copyright and database right 2026"), keeps the
"Woodland Or Forest" and "Other Landcover" entries (woods, plantations,
heaths, moors, commons) and writes assets/places/os_woods.tsv.gz: one line a
place, name, kind (w wood, l other landcover) and its box in WGS84 to four
decimals (south, west, north, east). Download the CSV from
https://osdatahub.os.uk/downloads/open/OpenNames.

British National Grid is turned into WGS84 with the usual inverse
Transverse Mercator on Airy 1830 and a seven-parameter Helmert shift (good to
about 5 m: plenty for a box of at least 500 m).
"""
import csv
import glob
import gzip
import math
import os
import sys

KINDS = {'Woodland Or Forest': 'w', 'Other Landcover': 'l'}

# Airy 1830, National Grid
A, B = 6377563.396, 6356256.909
F0, LAT0, LON0 = 0.9996012717, math.radians(49), math.radians(-2)
N0, E0 = -100000, 400000


def osgb36(e, n):
    """National Grid easting/northing to OSGB36 latitude/longitude (radians)."""
    e2 = 1 - (B * B) / (A * A)
    nn = (A - B) / (A + B)
    lat, m = LAT0, 0.0
    while True:
        lat = (n - N0 - m) / (A * F0) + lat
        m = B * F0 * (
            (1 + nn + 5 / 4 * nn**2 + 5 / 4 * nn**3) * (lat - LAT0)
            - (3 * nn + 3 * nn**2 + 21 / 8 * nn**3) * math.sin(lat - LAT0) * math.cos(lat + LAT0)
            + (15 / 8 * nn**2 + 15 / 8 * nn**3) * math.sin(2 * (lat - LAT0)) * math.cos(2 * (lat + LAT0))
            - 35 / 24 * nn**3 * math.sin(3 * (lat - LAT0)) * math.cos(3 * (lat + LAT0)))
        if abs(n - N0 - m) < 0.00001:
            break
    s, c, t = math.sin(lat), math.cos(lat), math.tan(lat)
    nu = A * F0 / math.sqrt(1 - e2 * s * s)
    rho = A * F0 * (1 - e2) / (1 - e2 * s * s) ** 1.5
    eta2 = nu / rho - 1
    vii = t / (2 * rho * nu)
    viii = t / (24 * rho * nu**3) * (5 + 3 * t * t + eta2 - 9 * t * t * eta2)
    ix = t / (720 * rho * nu**5) * (61 + 90 * t * t + 45 * t**4)
    x = 1 / (c * nu)
    xi = 1 / (c * 6 * nu**3) * (nu / rho + 2 * t * t)
    xii = 1 / (c * 120 * nu**5) * (5 + 28 * t * t + 24 * t**4)
    xiia = 1 / (c * 5040 * nu**7) * (61 + 662 * t * t + 1320 * t**4 + 720 * t**6)
    de = e - E0
    return (lat - vii * de**2 + viii * de**4 - ix * de**6,
            LON0 + x * de - xi * de**3 + xii * de**5 - xiia * de**7)


def wgs84(e, n):
    """National Grid to WGS84 latitude/longitude in degrees."""
    lat, lon = osgb36(e, n)
    # OSGB36 to cartesian on Airy
    e2 = 1 - (B * B) / (A * A)
    nu = A / math.sqrt(1 - e2 * math.sin(lat) ** 2)
    x = nu * math.cos(lat) * math.cos(lon)
    y = nu * math.cos(lat) * math.sin(lon)
    z = (1 - e2) * nu * math.sin(lat)
    # Helmert, OSGB36 to WGS84
    tx, ty, tz = 446.448, -125.157, 542.060
    sc = -20.4894e-6
    rx, ry, rz = (math.radians(v / 3600) for v in (0.1502, 0.2470, 0.8421))
    x2 = tx + (1 + sc) * x - rz * y + ry * z
    y2 = ty + rz * x + (1 + sc) * y - rx * z
    z2 = tz - ry * x + rx * y + (1 + sc) * z
    # back to latitude/longitude on WGS84
    a, b = 6378137.000, 6356752.3142
    e2 = 1 - (b * b) / (a * a)
    p = math.hypot(x2, y2)
    lat = math.atan2(z2, p * (1 - e2))
    for _ in range(10):
        nu = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
        lat = math.atan2(z2 + e2 * nu * math.sin(lat), p)
    return math.degrees(lat), math.degrees(math.atan2(y2, x2))


def main(folder):
    out = os.path.join(os.path.dirname(__file__), '..', 'assets', 'places', 'os_woods.tsv.gz')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    rows = []
    for path in sorted(glob.glob(os.path.join(folder, 'Data', '*.csv'))):
        with open(path, newline='', encoding='utf-8') as f:
            for r in csv.reader(f):
                kind = KINDS.get(r[7])
                if not kind or not r[2].strip():
                    continue
                s, w = wgs84(float(r[12]), float(r[13]))
                nth, est = wgs84(float(r[14]), float(r[15]))
                rows.append((r[2].strip().replace('\t', ' '), kind, s, w, nth, est))
    rows.sort(key=lambda r: (r[2], r[3]))
    with gzip.open(out, 'wt', encoding='utf-8', compresslevel=9) as f:
        for name, kind, s, w, n, e in rows:
            f.write(f'{name}\t{kind}\t{s:.4f}\t{w:.4f}\t{n:.4f}\t{e:.4f}\n')
    print(f'{len(rows)} places -> {os.path.normpath(out)} ({os.path.getsize(out)} bytes)')


if __name__ == '__main__':
    main(sys.argv[1])
