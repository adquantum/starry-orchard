extends RefCounted
## Project rating model, not a claim of exact equivalence to a particular retail era.
## Keep the existing rating scale; block reduces both landing chance and magnitude.
static func evaluate(rating: float, block: float, roll: float) -> Dictionary:
	rating = maxf(0.0, rating)
	block = maxf(0.0, block)
	var chance := minf(0.95, rating / (rating + block + 100.0))
	var critical := rating > 0.0 and roll < chance
	var multiplier := 1.0
	if critical:
		multiplier = 2.0 - 3.0 * block / (rating + 3.0 * block)
	return {"critical":critical,"multiplier":multiplier,"chance":chance}
