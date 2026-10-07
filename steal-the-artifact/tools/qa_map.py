#!/usr/bin/env python3
"""Release QA for the generated city.

    lune run tools/dump_map map.json
    python3 tools/qa_map.py map.json

Checks every prop/building model for:
  * floating   - its lowest point hangs in the air above whatever is under it
  * sunk       - furniture/vehicles/buildings pushed too far into the ground
  * in-wall    - a prop's solid core (or a tree's crown) pushed into a building body
  * on-road    - static props blocking a road surface (parked cars and street lights excepted)
  * overlap    - two solid props occupying the same space
and prints a performance budget. Exit code 1 if anything is flagged.

Geometry is approximated with axis-aligned boxes around each (possibly rotated) part,
which is plenty for spotting props that are visibly wrong.
"""

import json
import math
import sys
from collections import defaultdict

CELL = 16.0
LIMIT = 25

# Models that are whole areas, not props.
AREA_MODELS = {
    "Marketplace", "Museum", "Laboratory", "Temple", "Warehouse", "HighSecurityVault",
    "Underground", "VaultDoor", "Fountain", "WelcomeArch", "Gate", "DailyChest", "ParkingLot",
    "ConstructionSite", "Pond", "Gazebo", "StreetLife",
}
# Things that are meant to sit partly in the ground or on other props.
SINK_OK = {"Tree", "Pine", "Palm", "Bush", "Rocks", "TrashBags", "FlowerPot", "Tires", "UtilityPole", "Cone", "Crystals",
           "Mushroom", "Tuft", "Fern", "Wildflowers", "Stump", "Log"}
ROAD_OK = {"Car", "StreetLamp", "UtilityPole", "Cone", "Barrier", "TowerCrane", "Scaffold", "BusStop"}
# Furniture placed on purpose against/inside other objects.
OVERLAP_OK = {"Bush", "FlowerPot", "TrashBags", "FlowerBed", "Cone", "Bike", "Tires", "Lamp", "Rocks", "Tuft", "Fern",
              "Wildflowers"}
TREES = {"Tree", "Pine", "Palm"}
# Fixed to walls rather than standing on something.
WALL_MOUNTED = {"SecurityCamera"}


def box(part):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part["CFrame"]
    sx, sy, sz = (v / 2 for v in part["Size"])
    if part.get("Shape") == "Ball":
        m = min(sx, sy, sz)
        sx = sy = sz = m
    elif part.get("Shape") == "Cylinder":
        d = min(sy, sz)
        sy = sz = d
    hx = abs(r00) * sx + abs(r01) * sy + abs(r02) * sz
    hy = abs(r10) * sx + abs(r11) * sy + abs(r12) * sz
    hz = abs(r20) * sx + abs(r21) * sy + abs(r22) * sz
    return (x - hx, y - hy, z - hz, x + hx, y + hy, z + hz)


def overlap(a, b):
    dx = min(a[3], b[3]) - max(a[0], b[0])
    dy = min(a[4], b[4]) - max(a[1], b[1])
    dz = min(a[5], b[5]) - max(a[2], b[2])
    if dx <= 0 or dy <= 0 or dz <= 0:
        return 0.0
    return min(dx, dy, dz)


def obb(part):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part["CFrame"]
    sx, sy, sz = (v / 2 for v in part["Size"])
    if part.get("Shape") == "Ball":
        sx = sy = sz = min(sx, sy, sz)
    elif part.get("Shape") == "Cylinder":
        sy = sz = min(sy, sz)
    axes = ((r00, r10, r20), (r01, r11, r21), (r02, r12, r22))
    return ((x, y, z), axes, (sx, sy, sz))


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def penetration(a, b):
    """Separating-axis test between two oriented boxes; returns overlap depth (0 if apart)."""
    (ca, axa, ha), (cb, axb, hb) = a, b
    t = (cb[0] - ca[0], cb[1] - ca[1], cb[2] - ca[2])
    candidates = list(axa) + list(axb)
    for u in axa:
        for v in axb:
            c = cross(u, v)
            n = math.sqrt(dot(c, c))
            if n > 1e-6:
                candidates.append((c[0] / n, c[1] / n, c[2] / n))
    best = float("inf")
    for axis in candidates:
        ra = sum(ha[i] * abs(dot(axa[i], axis)) for i in range(3))
        rb = sum(hb[i] * abs(dot(axb[i], axis)) for i in range(3))
        depth = ra + rb - abs(dot(t, axis))
        if depth <= 0:
            return 0.0
        best = min(best, depth)
    return best


def merge(boxes):
    return (
        min(b[0] for b in boxes), min(b[1] for b in boxes), min(b[2] for b in boxes),
        max(b[3] for b in boxes), max(b[4] for b in boxes), max(b[5] for b in boxes),
    )


def main(path):
    data = json.load(open(path))
    parts = data["Parts"]
    mounds = data.get("Mounds", [])

    def ground(x, z, y):
        if y < -20:
            return -1e9  # underground: only parts count as support
        best = 0.0
        for m in mounds:
            cx, _, cz = m["Center"]
            d = math.hypot(x - cx, z - cz)
            if d < m["Radius"]:
                t = 1 - (d / m["Radius"]) ** 2
                best = max(best, m["Height"] * t * t)
        return best

    visible = []
    for i, p in enumerate(parts):
        if p["Transparency"] >= 0.98:
            continue
        b = box(p)
        p["_box"] = b
        visible.append(i)

    # Spatial hash of visible parts for support lookups.
    grid = defaultdict(list)
    for i in visible:
        b = parts[i]["_box"]
        for gx in range(int(math.floor(b[0] / CELL)), int(math.floor(b[3] / CELL)) + 1):
            for gz in range(int(math.floor(b[2] / CELL)), int(math.floor(b[5] / CELL)) + 1):
                grid[(gx, gz)].append(i)

    models = defaultdict(list)
    for i in visible:
        p = parts[i]
        if p.get("Model") and p.get("ModelName") not in AREA_MODELS and not str(p.get("ModelName", "")).startswith("Plot"):
            models[p["Model"]].append(i)

    issues = defaultdict(list)

    for i in visible:
        parts[i]["_obb"] = obb(parts[i])

    def contains(i, x, y, z, pad=0.0):
        (c, axes, h) = parts[i]["_obb"]
        d = (x - c[0], y - c[1], z - c[2])
        return all(abs(dot(d, axes[k])) <= h[k] + pad for k in range(3))

    def solid_at(x, y, z, exclude_model):
        if ground(x, z, y) > y:
            return True
        for i in grid[(int(math.floor(x / CELL)), int(math.floor(z / CELL)))]:
            p = parts[i]
            if p.get("Model") != exclude_model and p["Size"][1] > 0.1 and contains(i, x, y, z, 0.05):
                return True
        return False

    cores = {}
    for model, members in models.items():
        name = parts[members[0]]["ModelName"]
        if name in WALL_MOUNTED:
            continue
        boxes = [parts[i]["_box"] for i in members]
        bottom = min(b[1] for b in boxes)
        lowest = min(members, key=lambda i: parts[i]["_box"][1])
        b = parts[lowest]["_box"]
        cx, cz = (b[0] + b[3]) / 2, (b[2] + b[5]) / 2
        where_ = "(%.0f, %.0f, %.0f)" % (cx, bottom, cz)
        if not solid_at(cx, bottom - 0.35, cz, model):
            gap = 0.35
            while gap < 40 and not solid_at(cx, bottom - gap - 0.25, cz, model):
                gap += 0.25
            issues["floating"].append("%s at %s hangs %.1f studs above whatever is under it" % (name, where_, gap))
        elif name not in SINK_OK and solid_at(cx, bottom + 1.3, cz, model):
            issues["sunk"].append("%s at %s is buried more than 1.3 studs" % (name, where_))
        solid = [i for i in members if parts[i].get("CanCollide")]
        if solid:
            cores[model] = (name, merge([parts[i]["_box"] for i in solid]), solid)

    parent_of = {}
    for i in visible:
        p = parts[i]
        if p.get("Model") and p.get("ParentModel") and p["ParentModel"] != p["Model"]:
            parent_of[p["Model"]] = p["ParentModel"]

    def nested(a, b):
        for x, y in ((a, b), (b, a)):
            m = parent_of.get(x)
            while m:
                if m == y:
                    return True
                m = parent_of.get(m)
        return False

    def deepest(members_a, members_b):
        best = 0.0
        for i in members_a:
            for j in members_b:
                if overlap(parts[i]["_box"], parts[j]["_box"]) > 0:
                    best = max(best, penetration(parts[i]["_obb"], parts[j]["_obb"]))
        return best

    def where(core):
        return "(%.0f, %.0f)" % ((core[0] + core[3]) / 2, (core[2] + core[5]) / 2)

    bodies = [i for i in visible if parts[i]["Name"] == "Body" and parts[i]["Size"][1] > 8]
    roads = [i for i in visible if parts[i]["Name"] == "Road"]
    for model, (name, core, solid) in cores.items():
        for i in bodies:
            body = parts[i]
            if body.get("Model") == model or overlap(core, body["_box"]) <= 0:
                continue
            depth = deepest(solid, [i])
            if depth > 0.5:
                issues["in-wall"].append("%s pushes %.1f studs into %s near %s" % (name, depth, body.get("ModelName"), where(core)))
                break
        if name not in ROAD_OK:
            for i in roads:
                road = parts[i]
                if overlap(core, road["_box"]) > 0 and core[1] < road["_box"][4] + 0.2:
                    depth = deepest(solid, [i])
                    if depth > 0.6:
                        issues["on-road"].append("%s sits on a road near %s" % (name, where(core)))
                        break

    # Tree crowns don't collide, but leaves poking through a wall look just as wrong.
    # (Leaf masses are ellipsoids inside their boxes, hence the looser threshold.)
    for model, members in models.items():
        name = parts[members[0]]["ModelName"]
        if name not in TREES:
            continue
        crown = merge([parts[i]["_box"] for i in members])
        for i in bodies:
            body = parts[i]
            if overlap(crown, body["_box"]) <= 0:
                continue
            depth = deepest(members, [i])
            if depth > 2.0:
                issues["in-wall"].append("%s crown pushes %.1f studs into %s near %s" % (name, depth, body.get("ModelName"), where(crown)))
                break

    # Solid props occupying the same space
    buckets = defaultdict(list)
    for model, (name, core, solid) in cores.items():
        if name in OVERLAP_OK:
            continue
        for gx in range(int(math.floor(core[0] / CELL)), int(math.floor(core[3] / CELL)) + 1):
            for gz in range(int(math.floor(core[2] / CELL)), int(math.floor(core[5] / CELL)) + 1):
                buckets[(gx, gz)].append(model)
    seen = set()
    for members in buckets.values():
        for a in range(len(members)):
            for b in range(a + 1, len(members)):
                ma, mb = members[a], members[b]
                key = (min(ma, mb), max(ma, mb))
                if key in seen:
                    continue
                seen.add(key)
                na, ca, sa = cores[ma]
                nb, cb, sb = cores[mb]
                if overlap(ca, cb) <= 0 or nested(ma, mb):
                    continue
                if na in TREES and nb in TREES:
                    continue  # neighbouring canopies may intermingle
                depth = deepest(sa, sb)
                if depth > 0.8:
                    issues["overlap"].append("%s and %s overlap by %.1f near %s" % (na, nb, depth, where(ca)))

    # Budget
    total = len(parts)
    collide = sum(1 for p in parts if p.get("CanCollide"))
    shadows = sum(1 for p in parts if p.get("CastShadow"))
    transparent = sum(1 for p in parts if 0 < p["Transparency"] < 0.98)
    neon = sum(1 for p in parts if p["Material"] == "Neon")
    print("Budget: %d parts (%d collide, %d cast shadows, %d see-through, %d neon), %d lights, %d wires, %d text labels"
          % (total, collide, shadows, transparent, neon, len(data.get("Lights", [])), len(data.get("Beams", [])), len(data.get("Labels", []))))
    names = defaultdict(int)
    for model, members in models.items():
        names[parts[members[0]]["ModelName"]] += 1
    common = sorted(names.items(), key=lambda kv: -kv[1])[:12]
    print("Most repeated models: " + ", ".join("%s x%d" % kv for kv in common))

    flagged = 0
    for kind in ("floating", "sunk", "in-wall", "on-road", "overlap"):
        found = issues[kind]
        flagged += len(found)
        print("\n%s: %d" % (kind, len(found)))
        for line in found[:LIMIT]:
            print("  " + line)
        if len(found) > LIMIT:
            print("  ... and %d more" % (len(found) - LIMIT))
    return 1 if flagged else 0


if __name__ == "__main__":
    if "--all" in sys.argv:
        LIMIT = 10 ** 6
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sys.exit(main(args[0] if args else "map.json"))
