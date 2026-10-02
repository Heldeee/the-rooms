#!/usr/bin/env python3
"""Procedural texture generator for Uzine's liminal spaces (v2).

Rewrite of the original generator. The old version produced flat,
single-octave "hash noise" with duplicated-channel fake normal maps,
which is why everything looked muddy/plasticky in-engine and showed
seams every 2.5m (uv1_scale=4 on a 10m wall = the 256px tile repeats
4x, and the old noise wasn't actually tileable).

Fixes in this version:
  - True tileable value noise (bilinear lattice noise, wraps exactly
    at the texture edge) combined in multiple octaves (fbm) for real
    surface detail instead of a single blotchy frequency.
  - Real normal maps computed from the height field via a wraparound
    (toroidal) gradient, not a duplicated grayscale channel.
  - Stains/blobs use toroidal (wrap-aware) distance so they don't
    create a visible seam either.
  - 512x512 output (was 256x256) for crisper detail up close.
"""

import numpy as np
import os
from PIL import Image

OUTPUT_DIR = "textures"
SIZE = 512


# --------------------------------------------------------------------------
# Core tileable noise primitives
# --------------------------------------------------------------------------

def _smoothstep(t):
    return t * t * (3 - 2 * t)


def tileable_value_noise(size, period, seed):
    """Bilinear value noise on a wrap-around lattice. `period` must divide
    `size` evenly so the tiling is exact at the edges."""
    lattice = max(1, size // period)
    rng = np.random.RandomState(seed)
    grid = rng.rand(lattice, lattice).astype(np.float32)

    coords = np.arange(size, dtype=np.float32) / period
    i0 = np.floor(coords).astype(np.int64) % lattice
    i1 = (i0 + 1) % lattice
    t = _smoothstep(coords - np.floor(coords))

    y0, x0 = np.meshgrid(i0, i0, indexing="ij")
    y1, x1 = np.meshgrid(i1, i1, indexing="ij")
    ty, tx = np.meshgrid(t, t, indexing="ij")

    v00 = grid[y0, x0]
    v10 = grid[y0, x1]
    v01 = grid[y1, x0]
    v11 = grid[y1, x1]

    vx0 = v00 * (1 - tx) + v10 * tx
    vx1 = v01 * (1 - tx) + v11 * tx
    return vx0 * (1 - ty) + vx1 * ty  # 0..1


def fbm(size, seed, periods=(64, 32, 16, 8, 4)):
    """Fractal sum of tileable noise octaves. Returns 0..1."""
    total = np.zeros((size, size), dtype=np.float32)
    wsum = 0.0
    for i, p in enumerate(periods):
        w = 0.55 ** i
        total += tileable_value_noise(size, p, seed + i * 97) * w
        wsum += w
    return total / wsum


def _toroidal_delta(a, b, size):
    d = a - b
    d = np.where(d > size / 2, d - size, d)
    d = np.where(d < -size / 2, d + size, d)
    return d


def blob_field(size, count, seed, radius_range=(24, 70)):
    """Soft radial blobs (stains, mold patches, puddles...) that wrap
    seamlessly across the texture edges."""
    rng = np.random.RandomState(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    field = np.zeros((size, size), dtype=np.float32)
    for _ in range(count):
        cx = rng.uniform(0, size)
        cy = rng.uniform(0, size)
        r = rng.uniform(*radius_range)
        dx = _toroidal_delta(x, cx, size)
        dy = _toroidal_delta(y, cy, size)
        dist = np.sqrt(dx * dx + dy * dy)
        influence = np.clip(1.0 - dist / r, 0, 1)
        influence = _smoothstep(influence)
        field = np.maximum(field, influence)
    return field


def height_to_normal(height, strength=2.5):
    """Real tangent-space normal map from a height field, using a
    wraparound gradient so it tiles perfectly."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    nx, ny, nz = -dx, -dy, np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / length, ny / length, nz / length
    r = nx * 0.5 + 0.5
    g = ny * 0.5 + 0.5
    b = nz * 0.5 + 0.5
    return np.clip(np.stack([r, g, b, np.ones_like(r)], axis=-1) * 255, 0, 255).astype(np.uint8)


def tileable_cell_noise(size, period, seed):
    """Nearest-neighbour (non-interpolated) tileable noise: every `period`x
    `period` block of pixels gets one random value. Used for speckle/fleck
    patterns (carpet flecks, grain) where sharp per-cell dots look right,
    as opposed to the smooth blending of tileable_value_noise."""
    lattice = max(1, size // period)
    rng = np.random.RandomState(seed)
    grid = rng.rand(lattice, lattice).astype(np.float32)
    idx = (np.arange(size) // period) % lattice
    yi, xi = np.meshgrid(idx, idx, indexing="ij")
    return grid[yi, xi]


def save_rgba(arr01, path):
    img = np.clip(arr01 * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path)


def out(name):
    return os.path.join(OUTPUT_DIR, name)


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

def generate_carpet():
    """Speckled commercial/office carpet (the classic Backrooms look):
    a khaki/olive base, a fine woven-pile grain, and scattered multi-
    colour flecks (rust, teal, cream) like real Berber loop carpet —
    plus the same coarse stains as before. The flecks are what makes
    it actually read as carpet instead of a flat dirty floor."""
    grain = fbm(SIZE, 1001, periods=(64, 32, 16, 8, 4))
    coarse = fbm(SIZE, 1101, periods=(128, 64))
    y = np.arange(SIZE).reshape(-1, 1)
    weave = (np.sin(2 * np.pi * y * 40 / SIZE) * 0.5 + 0.5)  # integer freq -> tileable
    weave = np.repeat(weave, SIZE, axis=1)

    height = grain * 0.55 + coarse * 0.35 + weave * 0.10

    # Khaki/olive base (a bit greener and less muddy-brown than before)
    base_r = 0.34 + (height - 0.5) * 0.14
    base_g = 0.30 + (height - 0.5) * 0.13
    base_b = 0.20 + (height - 0.5) * 0.08

    # Fleck speckles: three colours, each its own sparse per-cell mask.
    fleck_cell = 3  # ~3px flecks at 512px -> reads as fine speckle, not blotches
    rust = tileable_cell_noise(SIZE, fleck_cell, 9001)
    teal = tileable_cell_noise(SIZE, fleck_cell, 9002)
    cream = tileable_cell_noise(SIZE, fleck_cell, 9003)

    rust_mask = (rust > 0.93).astype(np.float32)
    teal_mask = (teal > 0.95).astype(np.float32)
    cream_mask = (cream > 0.90).astype(np.float32)

    rust_color = np.array([0.55, 0.24, 0.14])
    teal_color = np.array([0.14, 0.32, 0.32])
    cream_color = np.array([0.72, 0.68, 0.52])

    base = np.stack([base_r, base_g, base_b], axis=-1)
    base = base * (1 - rust_mask[..., None]) + rust_color * rust_mask[..., None]
    base = base * (1 - teal_mask[..., None]) + teal_color * teal_mask[..., None]
    base = base * (1 - cream_mask[..., None]) + cream_color * cream_mask[..., None]
    base_r, base_g, base_b = base[..., 0], base[..., 1], base[..., 2]

    stain = blob_field(SIZE, 10, 2001, radius_range=(30, 90))
    base_r -= stain * 0.10
    base_g -= stain * 0.08
    base_b -= stain * 0.05

    save_rgba(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1), out("carpet_dirty.png"))
    # Normal map keeps the fine pile grain (not the flecks, which are pure
    # colour, not height) so the surface still reads as a soft woven carpet.
    save_rgba(height_to_normal(grain * 0.7 + coarse * 0.3, strength=3.2) / 255.0, out("carpet_dirty_normal.png"))
    print("  carpet_dirty (v3, speckled) done")


def generate_wallpaper():
    """Yellowed liminal wallpaper: subtle vertical stripe (integer freq,
    tileable), fine grain, and irregular age stains."""
    grain = fbm(SIZE, 2001, periods=(64, 32, 16, 8))
    x = np.arange(SIZE).reshape(1, -1)
    stripe = (np.sin(2 * np.pi * x * 24 / SIZE) * 0.5 + 0.5) ** 3
    stripe = np.repeat(stripe, SIZE, axis=0)

    height = grain * 0.75 + stripe * 0.25

    base_r = 0.70 + (height - 0.5) * 0.10
    base_g = 0.60 + (height - 0.5) * 0.09
    base_b = 0.30 + (height - 0.5) * 0.06

    age = blob_field(SIZE, 7, 3001, radius_range=(50, 140))
    base_r += age * 0.10
    base_g += age * 0.05
    base_b -= age * 0.03

    save_rgba(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1), out("wallpaper_yellow.png"))
    save_rgba(height_to_normal(grain * 0.6 + stripe * 0.4, strength=2.0) / 255.0, out("wallpaper_yellow_normal.png"))
    print("  wallpaper_yellow (v2) done")


def generate_peeling_wallpaper():
    """Wallpaper with peeling sections revealing a damp layer beneath."""
    grain = fbm(SIZE, 7002, periods=(64, 32, 16, 8))
    peel = blob_field(SIZE, 18, 7001, radius_range=(20, 55))

    base_r = 0.70 + (grain - 0.5) * 0.08
    base_g = 0.60 + (grain - 0.5) * 0.07
    base_b = 0.32 + (grain - 0.5) * 0.05

    under_r, under_g, under_b = 0.33, 0.29, 0.24
    blend = np.clip((peel - 0.45) * 2.2, 0, 1)
    r = (1 - blend) * base_r + blend * under_r
    g = (1 - blend) * base_g + blend * under_g
    b = (1 - blend) * base_b + blend * under_b

    edge = np.clip(1 - np.abs(peel - 0.45) * 7, 0, 1) * 0.18
    r -= edge
    g -= edge
    b -= edge * 0.5

    save_rgba(np.stack([r, g, b, np.ones_like(r)], axis=-1), out("peeling_wallpaper.png"))
    save_rgba(height_to_normal(grain * 0.5 + peel * 0.5, strength=3.5) / 255.0, out("peeling_wallpaper_normal.png"))
    print("  peeling_wallpaper (v2) done")


def generate_ceiling():
    """Acoustic ceiling tile material — plain grimy panel texture, no painted
    grid lines. The grid framing is now real 3D geometry (props/ceiling_grid.tscn)
    so it lines up exactly with the light panels instead of a texture pattern
    that repeats at whatever pace uv1_scale happens to pick."""
    grain = fbm(SIZE, 3001, periods=(64, 32, 16, 8))

    base_r = 0.80 + (grain - 0.5) * 0.07
    base_g = 0.78 + (grain - 0.5) * 0.06
    base_b = 0.70 + (grain - 0.5) * 0.06

    water = blob_field(SIZE, 5, 4001, radius_range=(50, 130))
    base_r -= water * 0.05
    base_g -= water * 0.04
    base_b -= water * 0.02
    base_r += water * 0.03

    save_rgba(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1), out("ceiling_tiles.png"))
    save_rgba(height_to_normal(grain, strength=2.0) / 255.0, out("ceiling_tiles_normal.png"))
    print("  ceiling_tiles (v2) done")


def generate_concrete_floor():
    """Damp bare concrete: coarse blotching, fine aggregate grain, dark
    puddles."""
    fine = fbm(SIZE, 8001, periods=(32, 16, 8, 4))
    coarse = fbm(SIZE, 8002, periods=(128, 64))
    height = fine * 0.5 + coarse * 0.5

    base_r = 0.34 + (height - 0.5) * 0.14
    base_g = 0.32 + (height - 0.5) * 0.13
    base_b = 0.29 + (height - 0.5) * 0.11

    puddle = blob_field(SIZE, 6, 8003, radius_range=(35, 100))
    base_r -= puddle * 0.09
    base_g -= puddle * 0.08
    base_b -= puddle * 0.06

    save_rgba(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1), out("concrete_floor.png"))
    save_rgba(height_to_normal(fine * 0.7 + coarse * 0.3, strength=2.8) / 255.0, out("concrete_floor_normal.png"))
    print("  concrete_floor (v2) done")


def generate_water_stains():
    """Transparent brownish water-stain overlay."""
    rng = np.random.RandomState(4001)
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    r = np.full((SIZE, SIZE), 0.55, dtype=np.float32)
    g = np.full((SIZE, SIZE), 0.48, dtype=np.float32)
    b = np.full((SIZE, SIZE), 0.30, dtype=np.float32)
    a = np.zeros((SIZE, SIZE), dtype=np.float32)

    for i in range(7):
        cx = rng.uniform(0, SIZE)
        cy = rng.uniform(0, SIZE)
        radius = rng.uniform(50, 160)
        dx = _toroidal_delta(x, cx, SIZE)
        dy = _toroidal_delta(y, cy, SIZE)
        dist = np.sqrt(dx * dx + dy * dy)
        factor = _smoothstep(np.clip(1.0 - dist / radius, 0, 1))
        r -= factor * 0.10
        g -= factor * 0.07
        b -= factor * 0.03
        a += factor * 0.55
        edge = np.clip(factor - 0.35, 0, 0.3) / 0.3
        r += edge * 0.05
        g += edge * 0.025

    save_rgba(np.stack([r, g, b, np.clip(a, 0, 1)], axis=-1), out("water_stains.png"))
    print("  water_stains (v2) done")


def generate_mold():
    """Transparent dark green-grey mold-patch overlay."""
    rng = np.random.RandomState(5001)
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    grain = fbm(SIZE, 5050, periods=(32, 16, 8))
    r = np.zeros((SIZE, SIZE), dtype=np.float32)
    g = np.zeros((SIZE, SIZE), dtype=np.float32)
    b = np.zeros((SIZE, SIZE), dtype=np.float32)
    a = np.zeros((SIZE, SIZE), dtype=np.float32)
    base_r, base_g, base_b = 0.14, 0.19, 0.12

    for _ in range(16):
        cx = rng.uniform(0, SIZE)
        cy = rng.uniform(0, SIZE)
        radius = rng.uniform(18, 55)
        dx = _toroidal_delta(x, cx, SIZE)
        dy = _toroidal_delta(y, cy, SIZE)
        dist = np.sqrt(dx * dx + dy * dy) - grain * 10.0  # ragged edge
        factor = np.clip(1.0 - dist / radius, 0, 1) ** 2
        coverage = factor * 0.22
        r += coverage
        g += coverage * 0.95
        b += coverage * 0.7
        a += coverage * 0.6

    a = np.clip(a, 0, 0.75)
    save_rgba(np.stack([r + base_r * a, g + base_g * a, b + base_b * a, a], axis=-1), out("mold.png"))
    print("  mold (v2) done")


def generate_wiring():
    """Transparent exposed-wiring overlay: irregular line segments."""
    rng = np.random.RandomState(6001)
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    r = np.zeros((SIZE, SIZE), dtype=np.float32)
    g = np.zeros((SIZE, SIZE), dtype=np.float32)
    b = np.zeros((SIZE, SIZE), dtype=np.float32)
    a = np.zeros((SIZE, SIZE), dtype=np.float32)

    for _ in range(12):
        x1 = rng.uniform(0, SIZE)
        y1 = rng.uniform(0, SIZE)
        ang = rng.uniform(0, 2 * np.pi)
        length = rng.uniform(120, 320)
        x2 = x1 + np.cos(ang) * length
        y2 = y1 + np.sin(ang) * length

        dx, dy = x2 - x1, y2 - y1
        len_sq = dx * dx + dy * dy
        t = np.clip(((x - x1) * dx + (y - y1) * dy) / len_sq, 0, 1)
        proj_x = x1 + t * dx
        proj_y = y1 + t * dy
        dist = np.sqrt((x - proj_x) ** 2 + (y - proj_y) ** 2)
        wire_mask = dist < rng.uniform(2.5, 4.5)

        shade = rng.uniform(0.35, 0.6)
        r[wire_mask] = shade
        g[wire_mask] = shade * 0.65
        b[wire_mask] = shade * 0.3
        a[wire_mask] = 0.9

    save_rgba(np.stack([r, g, b, np.clip(a, 0, 1)], axis=-1), out("wiring.png"))
    print("  wiring (v2) done")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print("Generating textures (v2, %dx%d, seamless) to %s/ ..." % (SIZE, SIZE, OUTPUT_DIR))
    generate_carpet()
    generate_wallpaper()
    generate_peeling_wallpaper()
    generate_ceiling()
    generate_concrete_floor()
    generate_water_stains()
    generate_mold()
    generate_wiring()
    print("All textures regenerated. Re-import in Godot (or just reopen the project) to see them.")


if __name__ == "__main__":
    main()
