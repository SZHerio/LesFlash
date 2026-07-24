class_name SearchSeed
extends RefCounted

## Stable, isolated seed derivation for search zones. It never reads or advances
## the run RNG state; only the immutable seed of that stream is used as input.

const MODULUS := 2_147_483_647
const MULTIPLIER := 131


static func derive(
	run_seed: int,
	template_id: String,
	template_version: int,
	visit_index: int
) -> int:
	var accumulator := 17
	var material := "run:%d|%s|v%d|visit:%d|search-zone" % [
		run_seed,
		template_id,
		template_version,
		visit_index,
	]
	for byte_value: int in material.to_utf8_buffer():
		accumulator = (accumulator * MULTIPLIER + byte_value + 17) % MODULUS
	return accumulator if accumulator != 0 else 1


static func stream_id(template_id: String, template_version: int, visit_index: int) -> String:
	return "search:%s:v%d:visit:%d" % [template_id, template_version, visit_index]
