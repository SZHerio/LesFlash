class_name JobShiftSeed
extends RefCounted

## Isolated stable seed derivation. Generating or reading a shift never advances
## the run-owned RNG stream.

const MODULUS := 2_147_483_647
const MULTIPLIER := 131
const GENERATOR_VERSION := 1


static func derive(run_seed: int, job_id: String, sequence: int, catalog_version: int) -> int:
	var material := "run:%d|job:%s|sequence:%d|catalog:v%d|generator:v%d" % [
		run_seed,
		job_id,
		sequence,
		catalog_version,
		GENERATOR_VERSION,
	]
	var accumulator := 29
	for byte_value: int in material.to_utf8_buffer():
		accumulator = (accumulator * MULTIPLIER + byte_value + 31) % MODULUS
	return accumulator if accumulator != 0 else 1


static func stream_id(job_id: String, sequence: int, catalog_version: int) -> String:
	return "job-shift:%s:v%d:sequence:%d" % [job_id, catalog_version, sequence]
