extends EditorScript
## Procedural texture generator for Uzine's liminal spaces.
## Generates PNG files for: carpet, wallpaper, ceiling tiles, water stains, mold,
## exposed wiring, peeling wallpaper, and concrete.
## 
## Run from Godot editor: Tools → Run Script
## Outputs to: res://textures/ directory

var rng := RandomNumberGenerator.new()
var output_dir: String = "res://textures/"

func _run() -> void:
	rng.randomize()
	
	print("Starting texture generation...")
	
	_generate_directory()
	_generate_carpet()
	_generate_wallpaper()
	_generate_ceiling()
	_generate_water_stains()
	_generate_mold()
	_generate_wiring()
	_generate_peeling_wallpaper()
	_generate_concrete_floor()
	
	print("Done! Generated textures in %s" % output_dir)

func _generate_directory() -> void:
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_absolute(output_dir)
		dir.close()

# ==================== CARPET ====================
func _generate_carpet() -> void:
	# Base carpet texture — dirty beige/brown with noise
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	var base_r := 0.22 * 255
	var base_g := 0.18 * 255
	var base_b := 0.12 * 255
	
	for y in range(256):
		for x in range(256):
			# Base noise
			var noise := _fast_noise(x, y, 1001)
			var r := base_r + noise * 40
			var g := base_g + noise * 30
			var b := base_b + noise * 20
			
			# Add fiber-like streaks
			var fiber := sin(y * 0.5 + noise * 10) * 15
			r += fiber
			g += fiber * 0.8
			
			# Dark stains scattered
			var stain := _blob_noise(x, y, 50, 80, 200)
			if stain > 0:
				r -= stain * 30
				g -= stain * 25
				b -= stain * 15
			
			img.set_pixel(x, y, Color(r/255.0, g/255.0, b/255.0, 1.0))
	
	img.save_png(output_dir + "carpet_dirty.png")
	
	# Create normal map (fake bump from noise)
	var nimg := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var n := (_fast_noise(x, y, 1002) + 1.0) * 0.5
			nimg.set_pixel(x, y, Color(n, n, 1.0, 1.0))
	
	nimg.save_png(output_dir + "carpet_dirty_normal.png")
	
	print("Generated carpet_dirty")

# ==================== WALLPAPER ====================
func _generate_wallpaper() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	var base_r := 0.72 * 255
	var base_g := 0.65 * 255
	var base_b := 0.35 * 255
	
	for y in range(256):
		for x in range(256):
			var noise := _fast_noise(x, y, 2001)
			
			# Subtle pattern — faint horizontal lines (like wallpaper ridges)
			var ridge := sin(y * 0.1) * 10
			var noise_pattern := sin(x * 0.05) * sin(y * 0.05) * 8
			
			var r := base_r + noise * 30 + ridge + noise_pattern
			var g := base_g + noise * 25 + ridge * 0.8
			var b := base_b + noise * 15 + ridge * 0.5
			
			# Yellowing/staining
			var age_stain := _blob_noise(x, y, 80, 120, 150)
			if age_stain > 0:
				r += age_stain * 40
				g += age_stain * 20
				b -= age_stain * 10
			
			img.set_pixel(x, y, Color(r/255.0, g/255.0, b/255.0, 1.0))
	
	img.save_png(output_dir + "wallpaper_yellow.png")
	
	# Normal map
	var nimg := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var n := (_fast_noise(x, y, 2002) + 1.0) * 0.5
			nimg.set_pixel(x, y, Color(n, n, 1.0, 1.0))
	nimg.save_png(output_dir + "wallpaper_yellow_normal.png")
	
	print("Generated wallpaper_yellow")

# ==================== CEILING ====================
func _generate_ceiling() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	var base_r := 0.82 * 255
	var base_g := 0.80 * 255
	var base_b := 0.74 * 255
	
	for y in range(256):
		for x in range(256):
			var noise := _fast_noise(x, y, 3001)
			
			# Ceiling tile grid
			var tile_size := 64
			var tx := x % tile_size
			var ty := y % tile_size
			
			# Grid lines
			var is_grid_line = (tx < 2 or ty < 2 or tx >= tile_size - 1 or ty >= tile_size - 1)
			
			var r := base_r + noise * 20
			var g := base_g + noise * 18
			var b := base_b + noise * 15
			
			if is_grid_line:
				r -= 20
				g -= 20
				b -= 20
			
			# Water damage stains
			var water := _blob_noise(x, y, 60, 100, 250)
			if water > 0:
				r -= water * 40
				g -= water * 35
				b -= water * 20
				# Yellow halo
				r += water * 15
			
			# Slightly dirty edges
			var edge_dist = min(tx, min(ty, min(tile_size - tx, tile_size - ty)))
			if edge_dist < 5:
				r -= (5 - edge_dist) * 3
				g -= (5 - edge_dist) * 3
				b -= (5 - edge_dist) * 2
			
			img.set_pixel(x, y, Color(r/255.0, g/255.0, b/255.0, 1.0))
	
	img.save_png(output_dir + "ceiling_tiles.png")
	
	var nimg := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var tx := x % 64
			var ty := y % 64
			var n := (_fast_noise(x, y, 3002) + 1.0) * 0.5
			if tx < 2 or ty < 2:
				n *= 0.7
			nimg.set_pixel(x, y, Color(n, n, 1.0, 1.0))
	nimg.save_png(output_dir + "ceiling_tiles_normal.png")
	
	print("Generated ceiling_tiles")

# ==================== WATER STAINS ====================
func _generate_water_stains() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	for y in range(256):
		for x in range(256):
			var r := 0.7 * 255
			var g := 0.65 * 255
			var b := 0.4 * 255
			
			# Multiple water stain blobs
			for i in range(5):
				var cx := (_fast_noise(i * 100, 0, 4001) + 1.0) * 0.5 * 256
				var cy := (_fast_noise(0, i * 100, 4002) + 1.0) * 0.5 * 256
				var radius := 20 + i * 8
				
				var dist = sqrt((x - cx) ** 2 + (y - cy) ** 2)
				if dist < radius:
					var factor := 1.0 - (dist / radius)
					factor = factor * factor * (3 - 2 * factor) # smoothstep
					
					r -= factor * 80
					g -= factor * 60
					b -= factor * 30
					
					# Brown edges
					if dist > radius * 0.7:
						r += factor * 30
						g += factor * 15
						b -= factor * 10
			
			img.set_pixel(x, y, Color(r/255.0, g/255.0, b/255.0, 1.0))
	
	img.save_png(output_dir + "water_stains.png")
	
	var nimg := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var n := (_fast_noise(x, y, 4003) + 1.0) * 0.5
			nimg.set_pixel(x, y, Color(n, n, 1.0, 1.0))
	nimg.save_png(output_dir + "water_stains_normal.png")
	
	print("Generated water_stains")

# ==================== MOLD ====================
func _generate_mold() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	# Start with transparent (alpha)
	for y in range(256):
		for x in range(256):
			var mold_coverage := 0.0
			
			# Seed points for mold colonies
			for i in range(10):
				var cx := (_fast_noise(i * 50, 0, 5001) + 1.0) * 0.5 * 256
				var cy := (_fast_noise(0, i * 50, 5002) + 1.0) * 0.5 * 256
				
				var dist = sqrt((x - cx) ** 2 + (y - cy) ** 2)
				if dist < 40:
					var factor := 1.0 - (dist / 40)
					factor = factor * factor
					mold_coverage += factor * 0.3
			
			mold_coverage = clamp(mold_coverage, 0.0, 1.0)
			
			var alpha := mold_coverage * 0.7
			
			# Mold color: dark green-grey
			var r := 0.15 * 255 + mold_coverage * 40
			var g := 0.20 * 255 + mold_coverage * 30
			var b := 0.12 * 255
			
			img.set_pixel(x, y, Color(r/255.0, g/255.0, b/255.0, alpha))
	
	img.save_png(output_dir + "mold.png")
	
	print("Generated mold")

# ==================== WIRING ====================
func _generate_wiring() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	for y in range(256):
		for x in range(256):
			var r := 0.6 * 255
			var g := 0.55 * 255
			var b := 0.35 * 255
			
			# Random exposed wire lines
			for i in range(8):
				var x1 := (_fast_noise(i * 30, 0, 6001) + 1.0) * 0.5 * 256
				var y1 := (_fast_noise(0, i * 30, 6002) + 1.0) * 0.5 * 256
				var x2 := x1 + (_fast_noise(i * 30, 30, 6003) - 0.5) * 150
				var y2 := y1 + (_fast_noise(30, i * 30, 6004) - 0.5) * 150
				
				var dist := _point_to_line_dist(x, y, x1, y1, x2, y2)
				if dist < 3:
					var wire_color = 0.4 + _fast_noise(i, x, y) * 0.15
					r += wire_color * 80
					g += wire_color * 60
					b += wire_color * 20
			
			img.set_pixel(x, y, Color(r/255.0, g/255.0, b/255.0, 1.0))
	
	img.save_png(output_dir + "wiring.png")
	
	print("Generated wiring")

# ==================== PEELING WALLPAPER ====================
func _generate_peeling_wallpaper() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	for y in range(256):
		for x in range(256):
			var base_r := 0.70 * 255
			var base_g := 0.63 * 255
			var base_b := 0.38 * 255
			
			# Peeling areas — random patches
			var peel := _blob_noise(x, y, 30, 60, 7001)
			if peel > 0.5:
				# Underneath layer — darker, damp
				base_r = 0.35 * 255
				base_g = 0.30 * 255
				base_b = 0.25 * 255
				
				# Edge darkening (shadow under peel)
				var edge_factor := 1.0 - abs(peel - 0.5) * 4.0
				if edge_factor > 0:
					base_r *= 0.7
					base_g *= 0.7
					base_b *= 0.7
			else:
				# Wallpaper layer with noise
				var noise := _fast_noise(x, y, 7002)
				base_r += noise * 25
				base_g += noise * 20
				base_b += noise * 15
			
			img.set_pixel(x, y, Color(base_r/255.0, base_g/255.0, base_b/255.0, 1.0))
	
	img.save_png(output_dir + "peeling_wallpaper.png")
	
	var nimg := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var peel := _blob_noise(x, y, 30, 60, 7001)
			var bump := peel * 0.3 + _fast_noise(x, y, 7003) * 0.1
			var n := 0.5 + bump
			nimg.set_pixel(x, y, Color(n, n, 1.0, 1.0))
	nimg.save_png(output_dir + "peeling_wallpaper_normal.png")
	
	print("Generated peeling_wallpaper")

# ==================== CONCRETE FLOOR ====================
func _generate_concrete_floor() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	var base_r := 0.35 * 255
	var base_g := 0.32 * 255
	var base_b := 0.28 * 255
	
	for y in range(256):
		for x in range(256):
			var noise := _fast_noise(x, y, 8001)
			var coarse := _fast_noise(x * 0.3, y * 0.3, 8002)
			
			var r := base_r + noise * 30 + coarse * 20
			var g := base_g + noise * 25 + coarse * 15
			var b := base_b + noise * 20 + coarse * 10
			
			# Puddles/wet spots
			var puddle := _blob_noise(x, y, 40, 80, 8003)
			if puddle > 0.3:
				r -= puddle * 40
				g -= puddle * 30
				b -= puddle * 15
			
			img.set_pixel(x, y, Color(r/255.0, g/255.0, b/255.0, 1.0))
	
	img.save_png(output_dir + "concrete_floor.png")
	
	var nimg := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var n := (_fast_noise(x, y, 8004) + 1.0) * 0.5
			nimg.set_pixel(x, y, Color(n, n, 1.0, 1.0))
	nimg.save_png(output_dir + "concrete_floor_normal.png")
	
	print("Generated concrete_floor")

# ==================== NOISE HELPERS ====================

# Fast hash-based noise (not perfect but good enough for procedural textures)
func _fast_noise(x: int, y: int, seed: int) -> float:
	var n = sin(float(x * 127.1 + y * 311.7 + seed) * 43758.5453)
	return n - floor(n) * 2.0 - 1.0  # Range: -1 to 1

# Blob noise — creates organic-looking blobs at specified positions
func _blob_noise(x: int, y: int, blob_count: int, blob_size: int, seed_base: int) -> float:
	var max_val := 0.0
	for i in range(blob_count):
		var cx := (_fast_noise(i * 7 + int(seed_base / 100), 0, seed_base) + 1.0) * 0.5 * 256
		var cy := (_fast_noise(0, i * 7 + int(seed_base / 100), seed_base + i) + 1.0) * 0.5 * 256
		var dist := sqrt((x - cx) ** 2 + (y - cy) ** 2)
		var influence := 1.0 - (dist / (blob_size + _fast_noise(i, 0, seed_base + 50) * 20))
		if influence > 0:
			influence = influence * influence * (3 - 2 * influence)
			max_val = max(max_val, influence)
	return max_val

# Distance from point to line segment
func _point_to_line_dist(px: int, py: int, x1: float, y1: float, x2: float, y2: float) -> float:
	var dx := x2 - x1
	var dy := y2 - y1
	var len_sq := dx * dx + dy * dy
	if len_sq == 0:
		return sqrt((px - x1) ** 2 + (py - y1) ** 2)
	
	var t = clamp(((px - x1) * dx + (py - y1) * dy) / len_sq, 0.0, 1.0)
	var proj_x := x1 + t * dx
	var proj_y := y1 + t * dy
	return sqrt((px - proj_x) ** 2 + (py - proj_y) ** 2)
