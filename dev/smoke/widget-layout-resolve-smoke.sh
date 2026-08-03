#!/usr/bin/env bash
# widget-layout-resolve-smoke — host gate: free/snap resolve stays cheap under load
# (regression: pitch-8 full-surface spiral froze Quickshell on free-drag).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAYOUT="${ROOT}/shell/surfaces/desktop/DesktopLayout.qml"

die() { echo "widget-layout-resolve-smoke: FAIL $*" >&2; exit 1; }
ok() { echo "widget-layout-resolve-smoke: OK $*"; }

[[ -f "${LAYOUT}" ]] || die "missing DesktopLayout.qml"
rg -q 'maxResolveRings' "${LAYOUT}" || die "missing maxResolveRings cap"
rg -q 'separateFromOthers' "${LAYOUT}" || die "missing separateFromOthers"
rg -q 'collidesAtWith' "${LAYOUT}" || die "missing collidesAtWith cache path"
# Must not spiral over the whole desktop (halfCols/halfRows + 2).
if rg -n 'ring <= Math\.max\(halfCols' "${LAYOUT}" >/dev/null; then
  die "uncapped halfCols spiral still present"
fi
# Pitch must stay coarse enough that grid draw + capped spiral stay light.
pitch="$(rg -o 'readonly property real pitch: [0-9]+' "${LAYOUT}" | head -1 | rg -o '[0-9]+')"
[[ -n "${pitch}" ]] || die "could not read pitch"
(( pitch >= 8 && pitch <= 40 )) || die "pitch ${pitch} out of expected range"
ok "layout guards (pitch=${pitch})"

# Algorithmic stress: same strategy as resolve (flush + separate + capped spiral).
python3 - <<'PY' || die "resolve stress"
import time

pitch = 16
max_rings = 12
W, H = 1920, 1080
margin = 8

def clamp(px, py, w, h):
    min_x = margin
    min_y = margin
    max_x = max(min_x, W - w - margin)
    max_y = max(min_y, H - h - margin)
    return max(min_x, min(max_x, px)), max(min_y, min(max_y, py))

def overlap(ax, ay, aw, ah, bx, by, bw, bh):
    return not (ax + aw <= bx or bx + bw <= ax or ay + ah <= by or by + bh <= ay)

def collides(others, px, py, w, h):
    return any(overlap(px, py, w, h, o[0], o[1], o[2], o[3]) for o in others)

def separate(others, px, py, w, h):
    x, y = px, py
    for _ in range(3):
        moved = False
        for ox, oy, ow, oh in others:
            if not overlap(x, y, w, h, ox, oy, ow, oh):
                continue
            pushes = [
                ((x + w) - ox, ox - w, y),
                ((ox + ow) - x, ox + ow, y),
                ((y + h) - oy, x, oy - h),
                ((oy + oh) - y, x, oy + oh),
            ]
            best = min(pushes, key=lambda t: t[0])
            nx, ny = clamp(best[1], best[2], w, h)
            if abs(nx - x) > 0.01 or abs(ny - y) > 0.01:
                x, y = nx, ny
                moved = True
        if not moved:
            break
    return x, y

def flush_cands(others, px, py, w, h):
    out = []
    for ox, oy, ow, oh in others:
        out += [
            (px, oy + oh), (px, oy - h), (ox + ow, py), (ox - w, py),
            (ox, oy + oh), (ox + ow - w, oy + oh), (ox + (ow - w) * 0.5, oy + oh),
            (ox, oy - h), (ox + ow - w, oy - h), (ox + (ow - w) * 0.5, oy - h),
            (ox + ow, oy), (ox + ow, oy + oh - h), (ox + ow, oy + (oh - h) * 0.5),
            (ox - w, oy), (ox - w, oy + oh - h), (ox - w, oy + (oh - h) * 0.5),
        ]
    return out

def resolve(others, px, py, w, h, snap=False):
    desired = clamp(px, py, w, h)
    if not collides(others, *desired, w, h):
        return desired
    best, best_d = None, 1e18
    for cx, cy in flush_cands(others, *desired, w, h):
        cand = clamp(cx, cy, w, h)
        if collides(others, *cand, w, h):
            continue
        d = abs(cand[0] - desired[0]) + abs(cand[1] - desired[1])
        if d < best_d:
            best_d, best = d, cand
    if best:
        return best
    sep = separate(others, *desired, w, h)
    if not collides(others, *sep, w, h):
        return sep
    step = pitch
    for ring in range(1, max_rings + 1):
        for dx in range(-ring, ring + 1):
            for dy in range(-ring, ring + 1):
                if max(abs(dx), abs(dy)) != ring:
                    continue
                cand = clamp(desired[0] + dx * step, desired[1] + dy * step, w, h)
                if not collides(others, *cand, w, h):
                    return cand
    return sep

# Cluster of widgets + drag path sweeping through them (free put hot path).
others = []
for i in range(12):
    others.append((200 + (i % 4) * 180, 120 + (i // 4) * 140, 160, 90))

# ~2.5k drag samples ≈ a long Customize drag; must stay well under 250ms/call-batch.
t0 = time.perf_counter()
n = 0
for y in range(80, 900, 20):
    for x in range(80, 1600, 20):
        resolve(others, x, y, 200, 96, snap=False)
        n += 1
elapsed_ms = (time.perf_counter() - t0) * 1000
if n < 1000:
    raise SystemExit(f"too few samples {n}")
# Per-call budget ≈ 0.2ms in CPython ⇒ 500ms for ~2.5k (QML is one call/move).
if elapsed_ms > 500:
    raise SystemExit(f"too slow: {n} resolves in {elapsed_ms:.0f}ms")
# Geometry: flush stack / side-dock; resolved seat must not overlap neighbors.
anchor = others[0]
ox, oy, ow, oh = anchor
w, h = 160, 80

fx, fy = resolve([anchor], ox, oy + 40, w, h)
if abs(fy - (oy + oh)) > 1:
    raise SystemExit(f"flush stack failed: got y={fy} want {oy + oh}")
if abs(fx - ox) > 1:
    raise SystemExit(f"flush stack x drift: got x={fx} want {ox}")
if collides([anchor], fx, fy, w, h):
    raise SystemExit("flush stack still overlaps anchor")

# Overlap from the right interior so resolve must pack flush to the right edge.
sx, sy = resolve([anchor], ox + ow - 24, oy + 4, w, h)
if abs(sx - (ox + ow)) > 1:
    raise SystemExit(f"flush side-dock failed: got x={sx} want {ox + ow}")
if collides([anchor], sx, sy, w, h):
    raise SystemExit("flush side-dock still overlaps anchor")

# Sweep: every resolve against the cluster must be non-overlapping.
for y in range(100, 800, 40):
    for x in range(100, 1500, 40):
        rx, ry = resolve(others, x, y, 180, 88)
        if collides(others, rx, ry, 180, 88):
            raise SystemExit(f"overlap after resolve at drag=({x},{y}) -> ({rx},{ry})")

print(f"resolve stress OK ({n} calls, {elapsed_ms:.0f}ms)")
print("resolve geometry OK (flush stack · side-dock · no overlap)")
PY

ok "resolve stress + geometry"
echo "widget-layout-resolve-smoke: OK"
