#!/usr/bin/env python3
"""Export one listening session's species list for the splash page.

Writes only what the page's test notifications need: each species in the
order it was first heard, how many times, and the best confidence. No
location, no recordings, no IDs (the repo is public).

    python3 -I tool/export_site_walk.py SESSION_FOLDER site/src/data/walk.json

SESSION_FOLDER is a folder under the app's data, e.g.
~/Library/Containers/uk.co.edstone.birdsongApp/Data/Library/Application Support/
uk.co.edstone.birdsongApp/sessions/2026-12-25T011100Z_16d985
"""
import json
import sys
from datetime import datetime


def main(folder, out, walk_number):
    session = json.load(open(f"{folder}/session.json"))
    start = datetime.fromisoformat(session["startTime"].replace("Z", "+00:00"))
    species = {}
    for line in open(f"{folder}/detections.jsonl"):
        if not line.strip():
            continue
        d = json.loads(line)
        sci = d["scientificName"]
        heard = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
        s = species.setdefault(sci, {
            "common": d["commonName"],
            "scientific": sci,
            "firstHeardSeconds": round((heard - start).total_seconds()),
            "calls": 0,
            "confidence": 0.0,
        })
        s["calls"] += 1
        s["confidence"] = max(s["confidence"], round(d["confidence"], 3))
    walk = {
        "walk": walk_number,
        "date": start.strftime("%Y-%m-%d"),
        "species": sorted(species.values(), key=lambda s: s["firstHeardSeconds"]),
    }
    with open(out, "w") as f:
        json.dump(walk, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"{len(walk['species'])} species written to {out}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 20)
