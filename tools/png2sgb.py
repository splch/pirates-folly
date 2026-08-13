#!/usr/bin/env python3
"""Convert a 256x224 PNG into Super Game Boy border data (RGBDS asm).

Usage: png2sgb.py <in.png> <out.inc> <label_prefix> <rom_bank>

Emits, in one ROMX section:
  <prefix>_tiles  8192 B  - 256 SNES 4bpp tiles (tile 0 = blank/transparent)
  <prefix>_map    1856 B  - 32x28 little-endian map entries + Y-flipped copy
                            of the bottom row (the partly-visible 29th row)
  <prefix>_pal      96 B  - palettes 4-6, 16 RGB555 colors each, color 0 = 0

SGB border rules (pandocs "SGB Command Border"):
  * border CHR RAM holds 256 tiles; map entries reference tiles $00-$FF
  * map palettes are 4-6 only (three 15-color palettes; index 0 transparent)
  * the center 20x18 tiles must be the blank tile (GB screen shows through)
"""
import struct
import sys
import zlib
from collections import Counter

import numpy as np

W, H = 256, 224
# center 160x144 GB screen window, in 8x8 tile coords
CX0, CX1, CY0, CY1 = 6, 26, 5, 23
MAX_PALETTES = 3
PAL_COLORS = 15  # per palette, excluding transparent index 0


def decode_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat = 8, b""
    w = h = ch = None
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos : pos + 4])
        typ = data[pos + 4 : pos + 8]
        if typ == b"IHDR":
            w, h, bd, ct, comp, filt, inter = struct.unpack(
                ">IIBBBBB", data[pos + 8 : pos + 8 + ln])
            assert bd == 8 and inter == 0, "need 8-bit non-interlaced PNG"
            assert ct in (2, 6), "need RGB or RGBA PNG"
            ch = 3 if ct == 2 else 4
        elif typ == b"IDAT":
            idat += data[pos + 8 : pos + 8 + ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * ch
    px = bytearray()
    prev = bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p : p + stride]); p += stride
        for i in range(stride):
            a = line[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        px += line
        prev = line
    out = []
    for i in range(0, len(px), ch):
        out.append((px[i], px[i + 1], px[i + 2]))
    assert (w, h) == (W, H), f"need {W}x{H}, got {w}x{h}"
    return out


def quantize(counts, target):
    """Merge nearest colors (count-weighted centroid) until <= target."""
    groups = [[c, n, [c]] for c, n in counts.items()]  # [centroid-sum, n, members]
    groups = [[[c[0] * n, c[1] * n, c[2] * n], n, [c]] for c, n in counts.items()]
    while len(groups) > target:
        best = None
        for i in range(len(groups)):
            gi = groups[i]
            ci = (gi[0][0] / gi[1], gi[0][1] / gi[1], gi[0][2] / gi[1])
            for j in range(i + 1, len(groups)):
                gj = groups[j]
                cj = (gj[0][0] / gj[1], gj[0][1] / gj[1], gj[0][2] / gj[1])
                d = sum((a - b) ** 2 for a, b in zip(ci, cj))
                if best is None or d < best[0]:
                    best = (d, i, j)
        _, i, j = best
        gi, gj = groups[i], groups[j]
        gi[0] = [a + b for a, b in zip(gi[0], gj[0])]
        gi[1] += gj[1]
        gi[2] += gj[2]
        del groups[j]
    mapping = {}
    for s, n, members in groups:
        centroid = (round(s[0] / n), round(s[1] / n), round(s[2] / n))
        for m in members:
            mapping[m] = centroid
    return mapping


def pack_palettes(tile_sets):
    """Best-fit-decreasing bin packing of tile color sets into <=3 palettes.

    Returns (palette list, tile->palette map) or None if infeasible."""
    pals = [set() for _ in range(MAX_PALETTES)]
    assign = {}
    order = sorted(tile_sets, key=lambda i: -len(tile_sets[i]))
    for i in order:
        s = tile_sets[i]
        best, best_extra = None, 99
        for p in range(MAX_PALETTES):
            if len(pals[p] | s) <= PAL_COLORS:
                extra = len(s - pals[p])
                if extra < best_extra:
                    best, best_extra = p, extra
        if best is None:
            return None
        pals[best] |= s
        assign[i] = best
    return pals, assign


def merge_tiles(patterns, freqs, limit):
    """Merge least-damaging tile pairs until <= limit unique patterns.

    patterns: list of 64-tuples (colors already quantized); freqs: parallel
    list of use counts. Returns position-pattern remap as {old_index: new}.
    Picks the pair with the fewest differing pixels and absorbs the rarer
    one into the more common one (texture variants merge invisibly)."""
    pats = [np.array(p, dtype=np.uint8) for p in patterns]
    # work on a small int code per color so array compares are meaningful
    colors = sorted({c for p in patterns for c in p})
    code = {c: i for i, c in enumerate(colors)}
    A = np.array([[code[c] for c in p] for p in patterns], dtype=np.uint8)
    freq = np.array(freqs, dtype=np.int64)
    alive = np.ones(len(patterns), dtype=bool)
    remap = {}
    while alive.sum() > limit:
        idx = np.flatnonzero(alive)
        sub = A[idx]
        # pairwise pixel-diff counts, in chunks to bound memory
        best = None
        for i0 in range(0, len(idx), 64):
            chunk = sub[i0 : i0 + 64]
            diff = (chunk[:, None, :] != sub[None, :, :]).sum(axis=2)
            for ci in range(diff.shape[0]):
                i = i0 + ci
                diff[ci, : i + 1] = 1 << 20  # upper triangle only
            j_flat = diff.argmin()
            ci, cj = divmod(int(j_flat), diff.shape[1])
            d = int(diff[ci, cj])
            if best is None or d < best[0]:
                best = (d, i0 + ci, cj)
        _, bi, bj = best
        gi, gj = int(idx[bi]), int(idx[bj])
        keep, drop = (gi, gj) if freq[gi] >= freq[gj] else (gj, gi)
        remap[drop] = keep
        alive[drop] = False
        freq[keep] += freq[drop]
    # resolve chains
    for k in remap:
        while remap[k] in remap:
            remap[k] = remap[remap[k]]
    return remap


def main():
    src, dst, label, bank = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    px = decode_png(src)

    # blank out the GB screen window: those tiles become tile 0
    def is_center(tx, ty):
        return CX0 <= tx < CX1 and CY0 <= ty < CY1

    # color census over border (non-center) pixels only
    counts = Counter()
    for ty in range(28):
        for tx in range(32):
            if is_center(tx, ty):
                continue
            for y in range(8):
                for x in range(8):
                    counts[px[(ty * 8 + y) * W + tx * 8 + x]] += 1

    # quantize + merge tiles until both limits hold: <=255 unique tiles
    # (tile 0 is the reserved blank) and 3 palette-packable color sets
    packed = patterns = index = uniq = None
    for target in range(45, 15, -1):
        m = quantize(counts, target) if len(counts) > target else {c: c for c in counts}
        pos_pat = {}
        for ty in range(28):
            for tx in range(32):
                if is_center(tx, ty):
                    continue
                pos_pat[(tx, ty)] = tuple(
                    m[px[(ty * 8 + y) * W + tx * 8 + x]]
                    for y in range(8) for x in range(8))
        # exact dedup with use counts
        u, freq, pidx = [], [], {}
        for pos in sorted(pos_pat, key=lambda p: (p[1], p[0])):
            pat = pos_pat[pos]
            if pat in pidx:
                freq[pidx[pat]] += 1
            else:
                pidx[pat] = len(u)
                u.append(pat)
                freq.append(1)
        if len(u) > 255:
            remap = merge_tiles(u, freq, 255)
            surv = sorted({remap.get(i, i) for i in range(len(u))})
            sidx = {s: n for n, s in enumerate(surv)}
            final = {i: sidx[remap.get(i, i)] for i in range(len(u))}
            u = [u[s] for s in surv]
        else:
            final = {i: i for i in range(len(u))}
        packed = pack_palettes({i: frozenset(p) for i, p in enumerate(u)})
        if packed:
            uniq = u
            # position -> merged unique index
            pos_idx = {pos: final[pidx[pos_pat[pos]]] for pos in pos_pat}
            break
    else:
        sys.exit(f"{src}: cannot satisfy SGB tile/palette limits")
    if len(counts) > 45:
        print(f"{label}: quantized {len(counts)} -> {target} colors")
    print(f"{label}: {len(uniq) + 1} unique tiles (incl. blank)")

    pals, assign = packed
    pals = [sorted(p) for p in pals]  # stable, cosmetic order
    ntiles = len(uniq) + 1

    def tile_bytes(pat):
        """64 palette indices -> 32-byte SNES 4bpp tile."""
        out = bytearray()
        for plane in (0, 2):
            for r in range(8):
                lo = hi = 0
                for x in range(8):
                    v = pat[r * 8 + x]
                    lo |= ((v >> plane) & 1) << (7 - x)
                    hi |= ((v >> (plane + 1)) & 1) << (7 - x)
                out += bytes((lo, hi))
        return bytes(out)

    # tile data: pattern -> 4bpp using its palette's color indices
    tiles = bytearray(256 * 32)
    for i, pat in enumerate(uniq):
        pal = pals[assign[i]]
        lut = {c: j + 1 for j, c in enumerate(pal)}
        indices = [lut[c] for c in pat]
        tiles[(i + 1) * 32 : (i + 1) * 32 + 32] = tile_bytes(indices)

    # map: entry = tile | ((4 + palette) << 10), little-endian
    entries = []
    for ty in range(28):
        for tx in range(32):
            if is_center(tx, ty):
                entries.append(0)  # blank tile, palette 4, transparent
            else:
                ui = pos_idx[(tx, ty)]
                entries.append((ui + 1) | ((4 + assign[ui]) << 10))
    # 29th row: bottom row Y-flipped (avoids 1-line flicker during SGB fades)
    entries += [e ^ 0x8000 for e in entries[27 * 32 : 28 * 32]]
    map_bytes = b"".join(struct.pack("<H", e) for e in entries)

    def rgb555(c):
        return (c[0] >> 3) | ((c[1] >> 3) << 5) | ((c[2] >> 3) << 10)

    pal_bytes = bytearray()
    for p in pals:
        pal_bytes += struct.pack("<H", 0)  # color 0: transparent
        for c in p:
            pal_bytes += struct.pack("<H", rgb555(c))
        pal_bytes += struct.pack("<H", 0) * (PAL_COLORS - len(p))
    assert len(pal_bytes) == 96 and len(map_bytes) == 1856

    def emit(f, data, per=16):
        for i in range(0, len(data), per):
            f.write("    db " + ",".join(f"${b:02X}" for b in data[i : i + per]) + "\n")

    with open(dst, "w") as f:
        f.write(f"; AUTO-GENERATED by tools/png2sgb.py from {src} -- do not edit\n")
        f.write(f'SECTION "{label} border", ROMX, BANK[{bank}]\n')
        f.write(f"{label}_tiles::\n")
        emit(f, tiles)
        f.write(f"{label}_map::\n")
        emit(f, map_bytes)
        f.write(f"{label}_pal::\n")
        emit(f, pal_bytes)
        f.write(f"    ASSERT {label}_map - {label}_tiles == 8192\n")
        f.write(f"    ASSERT {label}_pal - {label}_map == 1856\n")
    print(f"{label}: {ntiles} tiles, "
          f"palettes: {[len(p) for p in pals]} colors -> {dst}")


if __name__ == "__main__":
    main()
