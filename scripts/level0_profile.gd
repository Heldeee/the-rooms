extends RefCounted
class_name Level0Profile
## Stable spatial territories; revisits never reroll the world.
const REGION_SIZE: float = 48.0
const TRANSITION_WIDTH: float = 14.0
const PAPER := [Color(0.76, 0.68, 0.44), Color(0.74, 0.70, 0.53), Color(0.77, 0.68, 0.45), Color(0.70, 0.65, 0.46), Color(0.72, 0.69, 0.52), Color(0.79, 0.73, 0.55)]
const CARPET := [Color(0.44, 0.40, 0.30), Color(0.41, 0.40, 0.32), Color(0.43, 0.38, 0.28), Color(0.39, 0.36, 0.28), Color(0.41, 0.39, 0.31), Color(0.46, 0.42, 0.33)]
const LIGHT := [Color(1.0, 0.95, 0.84), Color(0.96, 0.97, 0.89), Color(1.0, 0.93, 0.80), Color(0.98, 0.94, 0.83), Color(0.95, 0.97, 0.87), Color(1.0, 0.98, 0.90)]
const NAMES := ["papier miel", "bureaux fanés", "moquette ocre", "humidité", "néons pâles", "ivoire ancien"]

static func biome(point: Vector2, seed_value: int) -> Dictionary:
	var cell := Vector2i(floori(point.x / REGION_SIZE), floori(point.y / REGION_SIZE))
	var candidates: Array[Dictionary] = []
	for x in range(cell.x - 1, cell.x + 2):
		for z in range(cell.y - 1, cell.y + 2):
			var random := RandomNumberGenerator.new()
			random.seed = hash("biome:%d:%d:%d" % [seed_value, x, z])
			var center := Vector2(x, z) * REGION_SIZE + Vector2(random.randf_range(0.25, 0.75), random.randf_range(0.25, 0.75)) * REGION_SIZE
			# One warm territory is deliberately centred on the start.
			if x == 0 and z == 0:
				center = Vector2.ZERO
			var kind := 0 if x == 0 and z == 0 else random.randi_range(0, 5)
			candidates.append({"distance": center.distance_to(point), "kind": kind, "cell": Vector2i(x, z)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var blend := 0.5 * (1.0 - smoothstep(0.0, TRANSITION_WIDTH, candidates[1].distance - candidates[0].distance))
	return {"primary": candidates[0].kind, "secondary": candidates[1].kind, "blend": blend, "region": candidates[0].cell}

static func palette(values: Array, info: Dictionary) -> Color:
	return values[info.primary].lerp(values[info.secondary], info.blend)

static func _terrace(axis: float, period: float, rise: float) -> float:
	# Bounded plateaus: no accumulated altitude, even thousands of metres away.
	var phase := fposmod(axis, period)
	return rise * (clampf((phase - 50.0) / 5.0, 0.0, 1.0) - clampf((phase - (period - 10.0)) / 5.0, 0.0, 1.0))

static func floor_height(point: Vector2) -> float:
	return _terrace(point.x, 120.0, 1.5) + _terrace(point.y, 180.0, 1.0)

static func chaos(distance_from_start: float) -> float:
	return smoothstep(65.0, 240.0, distance_from_start)
