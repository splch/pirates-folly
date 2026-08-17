#!/usr/bin/env python3
"""Exhaustive world proof: all 65,536 seas (every 16-bit folded seed).

The whole world is a pure function of wSeed16, so seed16 in [0, 65536)
enumerates every sea the game can generate. For each, this mirrors the
game's algorithms exactly (world.asm LatHash/Bilerp4/TerrainFull,
isles.asm ComputeIsles + FindSpawn, port.asm district hashes + TryDock's
beach rule) and asserts, for EVERY seed:

  1. spawn: FindSpawn accepts a candidate, or its fallback tile is water
  2. isles: all nine game-placed isle cells are distinct, contain land
     (full scan), have a diggable approach (a water tile in the cell next
     to land), and have at least one guardian spawn spot (of the game's 8
     spawn offsets, one lands on water from some approach tile)
  3. ports: at least one dockable port district exists (port hash + a
     TryDock-compatible beach: a water tile whose FIRST land neighbor in
     the game's N,S,W,E order lies in the port district)

Not checked (by design): full water connectivity from spawn to every
isle/port (value noise makes enclosed cells possible in principle; the
spawn scan's 24x12 water-run rule and the isles' center-ring placement
make it astronomically unlikely, and connectivity is a much more
expensive proof). If a failure ever appears, that is where to look.

Runtime: a few minutes with numpy. Offline proof; not part of make check.
A small ROM cross-check (4 seeds, via PyBoy) guards Python/asm drift.
"""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]

WORLD_W, WORLD_H = 320, 288

# ---------------------------------------------------------------- game mirrors

def mix16v(x):
    x = np.asarray(x, dtype=np.uint32)
    x ^= x >> 8
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF

# lattice indices: ix in 0..40, iy in 0..36
IXL = np.arange(41, dtype=np.uint32)[:, None]
IYL = np.arange(37, dtype=np.uint32)[None, :]

def land_grid(s):
    """(320, 288) bool: land (elevation >= 148) per world tile [x, y]."""
    L = mix16v((IXL * 97 + IYL * 61) ^ s) & 0xFF       # (41, 37)
    tx = np.arange(WORLD_W, dtype=np.int32)[:, None]
    ty = np.arange(WORLD_H, dtype=np.int32)[None, :]
    ix, fx = tx >> 3, tx & 7
    iy, fy = ty >> 3, ty & 7
    h00 = L[ix, iy].astype(np.int32)
    h10 = L[ix + 1, iy].astype(np.int32)
    h01 = L[ix, iy + 1].astype(np.int32)
    h11 = L[ix + 1, iy + 1].astype(np.int32)

    def lerp(a, b, f):
        d = b - a
        return np.where(d >= 0, a + ((d * f) >> 3), a - (((-d) * f) >> 3))

    e = lerp(lerp(h00, h10, fx), lerp(h01, h11, fx), fy)
    return e >= 148

# --- FindSpawn (world.asm): rows in order, +8 steps, 24-east/12-vertical ---
SPAWN_ROWS = [144, 160, 128, 176, 112, 192, 96, 208, 80, 224]

def spawn_ok(land):
    water = ~land
    # east run of >= 24 consecutive water tiles starting at each x
    for wy in SPAWN_ROWS:
        w = water[:, wy]
        cs = np.concatenate(([0], np.cumsum(w)))
        east24 = (cs[24:] - cs[:-24]) == 24          # east24[x]: run x..x+23
        # vertical water streaks in the row's columns, per candidate column
        col = water                                  # (320, 288)
        idx = np.arange(WORLD_H)
        for wx in range(8, WORLD_W - 8, 8):
            # out-of-world east tiles count as land (game's bounds check)
            if not (w[wx] and wx + 24 <= WORLD_W and east24[wx]):
                continue
            c = col[wx]
            # north: consecutive water directly above wy
            n = 1
            yc = wy
            while yc > 0 and n < 12 and c[yc - 1]:
                n += 1
                yc -= 1
            if n < 12:                               # south (cap row 250)
                yc = wy
                while yc < 250 and n < 12 and c[yc + 1]:
                    n += 1
                    yc += 1
            if n >= 12:
                return True
    # fallback (world.asm): tile (16, 144) must be water or the spawn is stuck
    return not land[16, 144]

# --- ComputeIsles (isles.asm): ring + jitter + 6-attempt land scan ---
ISLE_DX = [6, 5, 1, -3, -6, -6, -3, 1, 5]
ISLE_DY = [0, 4, 6, 5, 2, -2, -5, -6, -4]
ISLE_TRY = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1)]
CHL = [(10, 9), (5, 5), (15, 13)]

def _mix16_scalar(x):
    x &= 0xFFFF
    x ^= x >> 8
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF

def _clamp8(v):
    v &= 0xFF                     ; # 8-bit wrap like the asm
    if v >= 14:
        return 14
    return 1 if v == 0 else v

def compute_isles(s, land):
    """isles.asm ComputeIsles, incl. the dedup rule: an attempt is accepted
    only if it has land AND is distinct; if all six attempts fail, the
    FallbackFind scan walks the grid for (land && distinct), else takes
    the first distinct cell."""
    cells = []
    for k in range(9):
        h = _mix16_scalar(s ^ (k * 251))
        cx = _clamp8(8 + ISLE_DX[k] + ((h & 3) - 1))
        cy = _clamp8(8 + ISLE_DY[k] + (((h >> 12) & 3) - 1))
        pick = None
        for dx, dy in ISLE_TRY:
            ax, ay = (cx + dx) & 15, (cy + dy) & 15
            if (ax, ay) not in cells and \
               any(land[ax * 20 + ox, ay * 18 + oy] for ox, oy in CHL):
                pick = (ax, ay)
                break
        if pick is None:
            # FallbackFind: start from the attempt-5 cell and walk
            ax, ay = (cx + 1) & 15, (cy + 1) & 15
            stash = None
            for _ in range(255):
                ax = (ax + 1) & 15
                if ax == 0:
                    ay = (ay + 1) & 15
                if (ax, ay) in cells:
                    continue
                if stash is None:
                    stash = (ax, ay)
                if any(land[ax * 20 + ox, ay * 18 + oy] for ox, oy in CHL):
                    stash = (ax, ay)
                    break
            pick = stash if stash is not None else (ax, ay)
        cells.append(pick)
    return cells

# --- dockable ports (port.asm HasPortHash + TryDock's beach rule) ---
DXD = np.arange(80, dtype=np.uint32)[:, None]
DYD = np.arange(72, dtype=np.uint32)[None, :]

def port_grid(s):
    return (mix16v((DXD * 37 + DYD * 91) ^ s ^ 0x7E55) & 0x3F) < 12  # (80, 72)

def dockable_any(land, port):
    """Any TryDock-compatible beach: a water tile whose first land
    neighbor in the game's N,S,W,E order is in a port district."""
    water = ~land
    hit = np.zeros_like(water)
    blocked = np.zeros_like(water)
    gx0 = np.arange(WORLD_W)[:, None]
    gy0 = np.arange(WORLD_H)[None, :]
    for ddx, ddy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        bl = np.zeros_like(land)                     # land of the dir neighbor
        valid = np.zeros_like(water)                 # dir neighbor in-world
        xs = slice(max(0, ddx), WORLD_W + min(0, ddx))
        ys = slice(max(0, ddy), WORLD_H + min(0, ddy))
        xt = slice(max(0, -ddx), WORLD_W + min(0, -ddx))
        yt = slice(max(0, -ddy), WORLD_H + min(0, -ddy))
        bl[xt, yt] = land[xs, ys]
        valid[xt, yt] = True
        cand = water & ~blocked & bl & valid
        # beach district (of the neighbor tile), clipped to the port grid
        p = port[np.clip((gx0 + ddx) >> 2, 0, 79),
                 np.clip((gy0 + ddy) >> 2, 0, 71)]
        hit |= cand & p
        blocked |= bl
    return bool(hit.any())

# ------------------------------------------------------------- per-seed checks

# water tiles with a land 4-neighbor (dig approach), and guardian-spawnable
# tiles (some game spawn offset lands on water), both grid-wide
SPAWN_OFF = [(12, 0), (-13, 0), (0, 12), (0, -13), (7, 0), (-8, 0), (0, 7), (0, -8)]

def aux_grids(land):
    water = ~land
    nb = np.zeros_like(water)
    for ddx, ddy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        xs = slice(max(0, ddx), WORLD_W + min(0, ddx))
        ys = slice(max(0, ddy), WORLD_H + min(0, ddy))
        xt = slice(max(0, -ddx), WORLD_W + min(0, -ddx))
        yt = slice(max(0, -ddy), WORLD_H + min(0, -ddy))
        bl = np.zeros_like(land)
        bl[xt, yt] = land[xs, ys]
        nb |= bl
    water_with_land_nb = water & nb
    spawnable = np.zeros_like(water)
    for ox, oy in SPAWN_OFF:
        # spawn tile candidate = clamp(tile + off, 2, 318/286), must be water
        tx = np.clip(np.arange(WORLD_W)[:, None] + ox, 2, WORLD_W - 2)
        ty = np.clip(np.arange(WORLD_H)[None, :] + oy, 2, WORLD_H - 2)
        spawnable |= water & water[tx, ty]
    return water_with_land_nb, spawnable

dockable_any_cache = [False]

def sweep(a, b):
    failures = 0
    t0 = __import__("time").time()
    for s in range(a, b):
        land = land_grid(s)
        dockable_any_cache[0] = dockable_any(land, port_grid(s))
        wln, sp = aux_grids(land)
        problems = []
        if not spawn_ok(land):
            problems.append("spawn")
        cells = compute_isles(s, land)
        if len(set(cells)) != 9:
            problems.append(f"isle cells not distinct: {cells}")
        for i, (cx, cy) in enumerate(cells):
            cell = np.zeros_like(land)
            cell[cx * 20:(cx + 1) * 20, cy * 18:(cy + 1) * 18] = True
            if not land[cx * 20:(cx + 1) * 20, cy * 18:(cy + 1) * 18].any():
                problems.append(f"isle {i} at {cx},{cy}: no land")
                continue
            if not (wln & cell).any():
                problems.append(f"isle {i} at {cx},{cy}: no dig approach")
            if not (sp & cell).any():
                problems.append(f"isle {i} at {cx},{cy}: no guardian spot")
        if not dockable_any_cache[0]:
            problems.append("no dockable port")
        if problems:
            failures += 1
            print(f"seed16 {s:04X}: FAIL: {problems}")
            if failures >= 10:
                print("stopping after 10 failures")
                return 1
        if (s - a + 1) % 8192 == 0:
            el = __import__("time").time() - t0
            print(f"...{s - a + 1}/{b - a} seeds ({el:.0f}s), {failures} failures")
    return 1 if failures else 0

def rom_cross_check():
    """Verify the Python model against the live ROM for a few seeds
    (isle placement + spawn-on-water), guarding asm/Python drift."""
    try:
        from pyboy import PyBoy
    except ImportError:
        print("pyboy unavailable: skipping ROM cross-check")
        return 0
    import shutil
    import tempfile
    rom = str(ROOT / "pirates_folly.gb")
    sym = str(ROOT / "build" / "pirates_folly.sym")
    if not Path(rom).exists():
        print("no ROM built: skipping ROM cross-check")
        return 0
    syms = {}
    for line in open(sym):
        p = line.split()
        if len(p) == 2:
            syms[p[1]] = int(p[0].split(":")[1], 16)
    path = str(Path(tempfile.mkdtemp()) / "pf.gb")
    shutil.copy(rom, path)
    pb = PyBoy(path, window="null")
    pb.set_emulation_speed(0)
    mem = pb.memory
    for _ in range(150):
        pb.tick()
    pb.button_press("start"); pb.tick(); pb.button_release("start")
    for _ in range(10):
        pb.tick()
    seeds = [0xDEADBEEF, 0x00000001, 0xFFFFFFFF, 0x12345678]
    for seed in seeds:
        nib = [(seed >> (28 - 4 * i)) & 15 for i in range(8)]
        for i, n in enumerate(nib):
            mem[syms["wSeedNib"] + i] = n
        pb.button_press("a"); pb.tick(); pb.button_release("a")
        for _ in range(60):
            pb.tick()
        s16 = (mem[syms["wSeed16"]] << 8) | mem[syms["wSeed16"] + 1]
        land = land_grid(s16)
        want = compute_isles(s16, land)
        got = [(mem[syms["wIsles"] + 2 * k], mem[syms["wIsles"] + 2 * k + 1])
               for k in range(9)]
        if got != want:
            print(f"ROM cross-check FAIL {seed:08X}: isles {got} != model {want}")
            pb.stop()
            return 1
        px = mem[syms["wPosX"]] | mem[syms["wPosX"] + 1] << 8
        py = mem[syms["wPosY"]] | mem[syms["wPosY"] + 1] << 8
        if land[px >> 7, py >> 7]:
            print(f"ROM cross-check FAIL {seed:08X}: spawn on land")
            pb.stop()
            return 1
        # back to the editor for the next seed (B twice = quit confirm)
        for _ in range(2):
            pb.button_press("b"); pb.tick(); pb.button_release("b")
            for _ in range(30):
                pb.tick()
    pb.stop()
    print(f"ROM cross-check OK ({len(seeds)} seeds: isles + spawns match)")
    return 0

if __name__ == "__main__":
    a = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0
    b = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x10000
    rc = rom_cross_check()
    if rc == 0:
        rc = sweep(a, b)
    if rc == 0:
        print(f"ALL {b - a} SEAS PROVEN: spawn / isles / ports hold for every seed")
    sys.exit(rc)
