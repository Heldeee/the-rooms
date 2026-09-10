#!/usr/bin/env python3
"""Procedural texture generator for Uzine's liminal spaces.
Outputs PNG files to res://textures/ directory.
"""

import numpy as np
import os
from PIL import Image

OUTPUT_DIR = "textures"

def fast_noise(x, y, seed):
    n = np.sin(x * 127.1 + y * 311.7 + seed) * 43758.5453
    return (n % 1) * 2 - 1  # Range: -1 to 1

def blob_noise(x, y, blob_count, seed_base, blob_size_base=50):
    result = np.zeros((x.shape), dtype=np.float32)
    for i in range(blob_count):
        cx = (fast_noise(i * 7, 0, seed_base) * 0.5 + 0.5) * 256
        cy = (fast_noise(0, i * 7, seed_base + i) * 0.5 + 0.5) * 256
        size = blob_size_base + (fast_noise(i, 0, seed_base + 50) * 0.5 + 0.5) * 20
        dist = np.sqrt((x - cx)**2 + (y - cy)**2)
        influence = 1.0 - dist / size
        influence = np.clip(influence, 0, 1)
        influence = influence ** 2 * (3 - 2 * influence)
        result = np.maximum(result, influence)
    return result

def generate_carpet():
    """Dirty beige/brown carpet with stains and fiber streaks."""
    y, x = np.ogrid[0:256, 0:256]
    noise = fast_noise(x, y, 1001)
    
    base_r = 0.22 + noise * 0.05
    base_g = 0.18 + noise * 0.04
    base_b = 0.12 + noise * 0.03
    
    # Fiber streaks
    fiber = np.sin(y * 0.5 + noise * 10) * 0.03
    base_r += fiber
    base_g += fiber * 0.8
    
    # Dark stains
    stain = blob_noise(x, y, 8, 2001, blob_size_base=80)
    base_r -= stain * 0.08
    base_g -= stain * 0.06
    base_b -= stain * 0.04
    
    img = np.clip(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "carpet_dirty.png"))
    
    # Normal map
    n = (fast_noise(x, y, 1002) + 1) * 0.5
    normal = np.stack([n, n, np.ones_like(n), np.ones_like(n)], axis=-1) * 255
    Image.fromarray(normal.astype(np.uint8), "RGBA").save(os.path.join(OUTPUT_DIR, "carpet_dirty_normal.png"))
    print("  carpet_dirty ✓")

def generate_wallpaper():
    """Yellow liminal wallpaper with subtle pattern and age stains."""
    y, x = np.ogrid[0:256, 0:256]
    noise = fast_noise(x, y, 2001)
    
    base_r = 0.72 + noise * 0.04
    base_g = 0.65 + noise * 0.03
    base_b = 0.35 + noise * 0.02
    
    # Subtle ridges
    ridge = np.sin(y * 0.1) * 0.02
    noise_pattern = np.sin(x * 0.05) * np.sin(y * 0.05) * 0.02
    
    # Age stains
    age = blob_noise(x, y, 6, 3001, blob_size_base=120)
    base_r += age * 0.08
    base_g += age * 0.04
    base_b -= age * 0.02
    
    base_r += ridge + noise_pattern
    base_g += ridge * 0.8
    base_b += ridge * 0.5
    
    img = np.clip(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "wallpaper_yellow.png"))
    
    n = (fast_noise(x, y, 2002) + 1) * 0.5
    normal = np.stack([n, n, np.ones_like(n), np.ones_like(n)], axis=-1) * 255
    Image.fromarray(normal.astype(np.uint8), "RGBA").save(os.path.join(OUTPUT_DIR, "wallpaper_yellow_normal.png"))
    print("  wallpaper_yellow ✓")

def generate_ceiling():
    """White/off-white ceiling tiles with water damage and grid lines."""
    y, x = np.ogrid[0:256, 0:256]
    noise = fast_noise(x, y, 3001)
    
    base_r = 0.82 + noise * 0.03
    base_g = 0.80 + noise * 0.02
    base_b = 0.74 + noise * 0.02
    
    # Tile grid
    tile = 64
    tx = x % tile
    ty = y % tile
    is_grid = ((tx < 2) | (ty < 2) | (tx >= tile - 1) | (ty >= tile - 1))
    
    base_r[is_grid] -= 0.05
    base_g[is_grid] -= 0.05
    base_b[is_grid] -= 0.05
    
    # Water stains
    water = blob_noise(x, y, 4, 4001, blob_size_base=100)
    base_r -= water * 0.06
    base_g -= water * 0.05
    base_b -= water * 0.03
    base_r += water * 0.02  # yellow halo
    
    # Edge darkening
    edge_dist = np.minimum(np.minimum(tx, ty), np.minimum(tile - tx, tile - ty))
    edge_dark = np.clip(5 - edge_dist, 0, 1) * 3 / 255
    base_r -= edge_dark
    base_g -= edge_dark
    base_b -= edge_dark * 0.8
    
    img = np.clip(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "ceiling_tiles.png"))
    
    n = (fast_noise(x, y, 3002) + 1) * 0.5
    n[is_grid] *= 0.7
    normal = np.stack([n, n, np.ones_like(n), np.ones_like(n)], axis=-1) * 255
    Image.fromarray(normal.astype(np.uint8), "RGBA").save(os.path.join(OUTPUT_DIR, "ceiling_tiles_normal.png"))
    print("  ceiling_tiles ✓")

def generate_water_stains():
    """Transparent water stains overlay (can be used as a layer on walls/floor)."""
    y, x = np.ogrid[0:256, 0:256]
    
    r = np.full((256, 256), 0.7)
    g = np.full((256, 256), 0.65)
    b = np.full((256, 256), 0.4)
    a = np.zeros((256, 256), dtype=np.float32)
    
    for i in range(6):
        cx = (fast_noise(i * 100, 0, 4001) * 0.5 + 0.5) * 256
        cy = (fast_noise(0, i * 100, 4002) * 0.5 + 0.5) * 256
        radius = 30 + i * 15
        dist = np.sqrt((x - cx)**2 + (y - cy)**2)
        
        factor = np.clip(1.0 - dist / radius, 0, 1)
        factor = factor ** 2 * (3 - 2 * factor)
        
        r -= factor * 0.12
        g -= factor * 0.08
        b -= factor * 0.04
        a += factor * 0.5
        
        # Brown edges
        edge = np.clip(factor - 0.3, 0, 0.3) / 0.3
        r += edge * 0.06
        g += edge * 0.03
    
    img = np.clip(np.stack([r, g, b, np.clip(a, 0, 1)], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "water_stains.png"))
    print("  water_stains ✓")

def generate_mold():
    """Dark green-grey mold patches (transparent overlay)."""
    y, x = np.ogrid[0:256, 0:256]
    
    r = np.zeros((256, 256), dtype=np.float32)
    g = np.zeros((256, 256), dtype=np.float32)
    b = np.zeros((256, 256), dtype=np.float32)
    a = np.zeros((256, 256), dtype=np.float32)
    
    base_r, base_g, base_b = 0.15, 0.20, 0.12
    
    for i in range(12):
        cx = (fast_noise(i * 50, 0, 5001) * 0.5 + 0.5) * 256
        cy = (fast_noise(0, i * 50, 5002) * 0.5 + 0.5) * 256
        dist = np.sqrt((x - cx)**2 + (y - cy)**2)
        
        factor = np.clip(1.0 - dist / 40, 0, 1)
        factor = factor ** 2
        coverage = factor * 0.25
        
        r += coverage
        g += coverage * 0.9
        b += coverage * 0.7
        a += coverage * 0.6
    
    a = np.clip(a, 0, 0.7)
    
    img = np.clip(np.stack([r + base_r * a, g + base_g * a, b + base_b * a, a], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "mold.png"))
    print("  mold ✓")

def generate_wiring():
    """Exposed wiring on walls (transparent overlay)."""
    y, x = np.ogrid[0:256, 0:256]
    
    r = np.full((256, 256), 0.6)
    g = np.full((256, 256), 0.55)
    b = np.full((256, 256), 0.35)
    a = np.zeros((256, 256), dtype=np.float32)
    
    for i in range(10):
        x1 = (fast_noise(i * 30, 0, 6001) * 0.5 + 0.5) * 256
        y1 = (fast_noise(0, i * 30, 6002) * 0.5 + 0.5) * 256
        x2 = x1 + (fast_noise(i * 30, 30, 6003) - 0.5) * 150
        y2 = y1 + (fast_noise(30, i * 30, 6004) - 0.5) * 150
        
        dx, dy = x2 - x1, y2 - y1
        len_sq = dx**2 + dy**2
        t = np.clip(((x - x1) * dx + (y - y1) * dy) / len_sq, 0, 1)
        proj_x = x1 + t * dx
        proj_y = y1 + t * dy
        dist = np.sqrt((x - proj_x)**2 + (y - proj_y)**2)
        
        wire_mask = dist < 3
        
        # Wire color — per-pixel variation
        noise_val = (fast_noise(i * 10 + x, i * 10 + y, 6005) * 0.5 + 0.5)
        wire_r = 0.5 + noise_val * 0.3
        wire_g = 0.3 + noise_val * 0.2
        wire_b = 0.15 + noise_val * 0.1
        
        r[wire_mask] += wire_r[wire_mask]
        g[wire_mask] += wire_g[wire_mask]
        b[wire_mask] += wire_b[wire_mask]
        a[wire_mask] += 0.8
    
    a = np.clip(a, 0, 1)
    img = np.clip(np.stack([r, g, b, a], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "wiring.png"))
    print("  wiring ✓")

def generate_peeling_wallpaper():
    """Wallpaper with peeling sections revealing darker layer underneath."""
    y, x = np.ogrid[0:256, 0:256]
    
    peel = blob_noise(x, y, 15, 7001, blob_size_base=60)
    
    # Wallpaper layer
    base_r = 0.72 + fast_noise(x, y, 7002) * 0.03
    base_g = 0.65 + fast_noise(x, y, 7003) * 0.02
    base_b = 0.38 + fast_noise(x, y, 7004) * 0.015
    
    # Underneath layer (darker, damp)
    under_r, under_g, under_b = 0.35, 0.30, 0.25
    
    # Blend based on peel amount (0 = wallpaper, 1 = under layer)
    blend = np.clip((peel - 0.5) * 2, 0, 1)
    r = (1 - blend) * base_r + blend * under_r
    g = (1 - blend) * base_g + blend * under_g
    b = (1 - blend) * base_b + blend * under_b
    
    # Darker edges where peel starts (shadow under flap)
    edge_factor = np.abs(peel - 0.5)
    edge_shadow = np.clip(1 - edge_factor * 6, 0, 1) * 0.15
    r -= edge_shadow
    g -= edge_shadow
    b -= edge_shadow * 0.5
    
    img = np.clip(np.stack([r, g, b, np.ones_like(r)], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "peeling_wallpaper.png"))
    
    n = (fast_noise(x, y, 7005) + 1) * 0.5 + peel * 0.1
    normal = np.clip(np.stack([n, n, np.ones_like(n), np.ones_like(n)], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(normal, "RGBA").save(os.path.join(OUTPUT_DIR, "peeling_wallpaper_normal.png"))
    print("  peeling_wallpaper ✓")

def generate_concrete_floor():
    """Damp concrete floor with puddles."""
    y, x = np.ogrid[0:256, 0:256]
    noise = fast_noise(x, y, 8001)
    coarse = fast_noise(x * 0.3, y * 0.3, 8002)
    
    base_r = 0.35 + noise * 0.04 + coarse * 0.03
    base_g = 0.32 + noise * 0.03 + coarse * 0.02
    base_b = 0.28 + noise * 0.02 + coarse * 0.02
    
    # Puddles
    puddle = blob_noise(x, y, 5, 8003, blob_size_base=80)
    base_r -= puddle * 0.06
    base_g -= puddle * 0.04
    base_b -= puddle * 0.02
    
    img = np.clip(np.stack([base_r, base_g, base_b, np.ones_like(base_r)], axis=-1) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUTPUT_DIR, "concrete_floor.png"))
    
    n = (fast_noise(x, y, 8004) + 1) * 0.5
    normal = np.stack([n, n, np.ones_like(n), np.ones_like(n)], axis=-1) * 255
    Image.fromarray(normal.astype(np.uint8), "RGBA").save(os.path.join(OUTPUT_DIR, "concrete_floor_normal.png"))
    print("  concrete_floor ✓")

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print("Generating textures to %s/ ..." % OUTPUT_DIR)
    generate_carpet()
    generate_wallpaper()
    generate_ceiling()
    generate_water_stains()
    generate_mold()
    generate_wiring()
    generate_peeling_wallpaper()
    generate_concrete_floor()
    print("All textures generated!")

if __name__ == "__main__":
    main()
