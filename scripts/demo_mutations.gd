# ============================================================================
# demo_mutations.gd - Headless demo of the named mutation event system
# ============================================================================
# Breeds unstable bugs repeatedly and prints each mutation event to show
# the variety of outcomes. Run with:
#   godot --headless --path ~/localhost-game --script scripts/demo_mutations.gd
# ============================================================================

extends SceneTree

func _init() -> void:
	print("============================================================")
	print("LOCALHOST Mutation Event Demo")
	print("============================================================")
	print()

	# Create two bugs with very low stability (10%) so mutations are frequent
	# Mutation chance = (1.0 - avg_stability) * 0.5 = (1.0 - 0.1) * 0.5 = 0.45 (45%)
	var bug_a = Strain.create_seed()
	bug_a.strain_name = "Bug-Alpha"
	bug_a.stability = 0.1
	bug_a.stealth = 0.5
	bug_a.speed = 0.5
	bug_a.payload = 0.5
	bug_a.resilience = 0.5

	var bug_b = Strain.create_seed()
	bug_b.strain_name = "Bug-Beta"
	bug_b.stability = 0.1
	bug_b.stealth = 0.4
	bug_b.speed = 0.6
	bug_b.payload = 0.4
	bug_b.resilience = 0.6

	print("Parent A: %s (stability: %.0f%%)" % [bug_a.strain_name, bug_a.stability * 100])
	print("Parent B: %s (stability: %.0f%%)" % [bug_b.strain_name, bug_b.stability * 100])
	print("Mutation chance per breed: 45%%")
	print()

	# Breed 30 times and show each mutation event
	var mutations_count = 0
	var no_mutation_count = 0
	var event_types_seen = {}

	for i in range(30):
		var child = Breeding.breed(bug_a, bug_b)
		if child == null:
			continue

		var event_name = "None"
		var event_desc = ""
		var event_color = ""
		if not child.mutation_event.is_empty():
			event_name = child.mutation_event.get("event_name", "?")
			event_desc = child.mutation_event.get("event_desc", "")
			var color: Color = child.mutation_event.get("event_color", Color.WHITE)
			event_color = "rgb(%.0f,%.0f,%.0f)" % [color.r * 255, color.g * 255, color.b * 255]
			mutations_count += 1
			if not event_types_seen.has(event_name):
				event_types_seen[event_name] = 0
			event_types_seen[event_name] += 1
		else:
			no_mutation_count += 1

		# Print the result
		print("--- Breed #%02d ---" % (i + 1))
		print("  Child: %s (Gen %d)" % [child.strain_name, child.generation])
		print("  Stats: S%.0f Sp%.0f P%.0f R%.0f St%.0f" % [
			child.stealth * 100, child.speed * 100, child.payload * 100,
			child.resilience * 100, child.stability * 100
		])
		if event_name != "None":
			print("  *** MUTATION: %s ***" % event_name)
			print("  Color: %s" % event_color)
			print("  Desc: %s" % event_desc)
			# Print trait details
			var details = child.mutation_event.get("details", {})
			if not details.is_empty():
				for trait_name in details:
					var data = details[trait_name]
					print("    %s: %.0f%% -> %.0f%%" % [
						trait_name.capitalize(),
						data["old"] * 100,
						data["new"] * 100
					])
		else:
			print("  No mutation (stable breeding)")
		print()

	# Summary
	print("============================================================")
	print("SUMMARY")
	print("============================================================")
	print("Total breeds: 30")
	print("Mutations: %d (%.0f%%)" % [mutations_count, float(mutations_count) / 30.0 * 100])
	print("No mutations: %d (%.0f%%)" % [no_mutation_count, float(no_mutation_count) / 30.0 * 100])
	print()
	print("Event types seen:")
	for event_name in event_types_seen:
		print("  %s: %d" % [event_name, event_types_seen[event_name]])
	print("============================================================")

	quit()