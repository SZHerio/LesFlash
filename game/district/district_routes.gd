class_name DistrictRoutes
extends RefCounted

## Getting from one place in the district to another when they do not touch.
##
## The map model only ever knew about roads leading out of where the hero is
## standing, which is all a player needs — they can see the map and decide. Code
## that has to walk somewhere on its own needs more than that, and until now the
## only thing that could was the acceptance test, which carried its own copy of
## this search.
##
## The graph is small and unweighted for this purpose: the question is which way
## to step next, not which way is cheapest. Cost is decided at the crossing, by
## whoever is paying the fare.

const Content := preload("res://game/district/district_content.gd")


## The whole way there, starting with the origin and ending with the
## destination. Empty when there is no way at all.
static func path(origin: String, destination: String) -> Array[String]:
	var result: Array[String] = []
	if origin.is_empty() or destination.is_empty():
		return result
	if origin == destination:
		result.append(origin)
		return result
	var came_from: Dictionary = {origin: ""}
	var queue: Array[String] = [origin]
	var found := false
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == destination:
			found = true
			break
		for neighbour: String in exits_from(current):
			if came_from.has(neighbour):
				continue
			came_from[neighbour] = current
			queue.append(neighbour)
	if not found:
		return result
	var cursor := destination
	# The chain cannot loop — every node is written once — but the walk is
	# bounded anyway rather than trusted, the same way the search pathfinder is.
	var steps_allowed := came_from.size() + 1
	while not cursor.is_empty():
		steps_allowed -= 1
		if steps_allowed < 0:
			return [] as Array[String]
		result.push_front(cursor)
		cursor = String(came_from.get(cursor, ""))
	return result


## The next place to walk to on the way there, or empty if there is no way.
static func first_step(origin: String, destination: String) -> String:
	var route := path(origin, destination)
	if route.size() < 2:
		return ""
	return route[1]


## Where you can get to directly from here.
static func exits_from(location_id: String) -> Array[String]:
	var result: Array[String] = []
	for raw_route: Variant in Content.routes_from(location_id):
		if not raw_route is Dictionary:
			continue
		var destination := String(Dictionary(raw_route).get("destination_id", ""))
		if not destination.is_empty() and destination not in result:
			result.append(destination)
	return result


## Whether every place can be reached from every other. A road declared on one
## side and never on the other has stranded the hero before, and it is the kind
## of mistake that only shows up days into a run.
static func every_place_is_reachable() -> Dictionary:
	var unreachable: Array[String] = []
	var places: Array = Content.district().get("location_ids", [])
	for raw_origin: Variant in places:
		for raw_destination: Variant in places:
			var origin := String(raw_origin)
			var destination := String(raw_destination)
			if origin == destination:
				continue
			if path(origin, destination).is_empty():
				unreachable.append("%s -> %s" % [origin, destination])
	return {"ok": unreachable.is_empty(), "unreachable": unreachable}
