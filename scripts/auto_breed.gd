# ============================================================================
# auto_breed.gd - Headless script that breeds bugs and prints mutation events
# ============================================================================
# This simulates what would happen when the player clicks "Breed Strains"
# but runs headless so we can see the mutation event output without needing
# to interact with the GUI.
# ============================================================================

extends SceneTree

func _init() -> void:
	print("============================================================")
	print("LOCALHOST Auto-Breed Demo -- Mutation Events")
	print("============================================================")
	print()

	# Create two bugs with very low stability for high mutation chance
	var bug_a = Strain.create_seed()
	bug_a.strain_name = "Bug-Alpha"
	bug_a.stability = 0.05  # Very unstable = ~47.5% mutation chance
	bug_a.stealth = 0.5
	bug_a.speed = 0.5
	bug_a.payload = 0.5
	bug_a.resilience = 0.5
	bug_a.generation = 1

	var bug_b = Strain.create_seed()
	bug_b.strain_name = "Bug-Beta"
	bug_b.stability = 0.05
	bug_b.stealth = 0.4
	bug_b.speed = 0.6
	bug_b.payload = 0.6
	bug_b.resilience = 0.4
	bug_b.generation = 1

	print("Bug-Alpha: Stealth 50% Speed 50% Payload 50% Resilience 50% Stability 5%")
	print("Bug-Beta:  Stealth 40% Speed 60% Payload 60% Resilience 40% Stability 5%")
	print("Mutation chance: ~47.5% per breed")
	print()

	# Breed 20 times, looking for rare mutation types
	var mutation_count = 0
	var events = {}

	for i in range(20):
		var child = Breeding.breed(bug_a, bug_b)
		if child == null:
			continue

		var event_name = "No mutation"
		var event_desc = ""
		var event_color_str = ""
		var details_str = ""

		if not child.mutation_event.is_empty():
			event_name = child.mutation_event.get("event_name", "?")
			event_desc = child.mutation_event.get("event_desc", "")
			var color: Color = child.mutation_event.get("event_color", Color.WHITE)
			event_color_str = "rgb(%.0f,%.0f,%.0f)" % [color.r * 255, color.g * 255, color.b * 255]
			var details: Dictionary = child.mutation_event.get("details", {})
			if not details.is_empty():
				for trait_name in details:
					var data = details[trait_name]
					details_str += "    %s: %.0f%% -> %.0f%%\n" % [
						trait_name.capitalize(), data["old"] * 100, data["new"] * 100
					]
			mutation_count += 1
			if not events.has(event_name):
				events[event_name] = 0
			events[event_name] += 1

		print("--- Breed #%02d: %s (Gen %d) ---" % [i + 1, child.strain_name, child.generation])
		if event_name != "No mutation":
			print("  *** %s ***" % event_name)
			print("  Color: %s" % event_color_str)
			print("  %s" % event_desc)
			if details_str != "":
				print(details_str.rstrip("\n"))
		else:
			print("  No mutation")
		print()

	print("============================================================")
	print("RESULTS: %d mutations in 20 breeds (%.0f%%)" % [mutation_count, float(mutation_count) / 20.0 * 100])
	print("============================================================")
	for event_name in events:
		print("  %s: %d" % [event_name, events[event_name]])
	print("============================================================")

	quit()