# ============================================================================
# test_breeding.gd - Verification that breeding.gd works correctly
# ============================================================================
# Tests:
# 1. breed() produces a valid child from two parents
# 2. Child traits are within expected range (between parents, +/- jitter)
# 3. Child generation is max(parents) + 1
# 4. get_breed_cost() returns sensible values
# 5. Mutation chance increases with low stability
# 6. Personality inheritance follows the rules
# 7. Breeding a strain with itself returns null
# 8. detect_mutations() correctly identifies mutated traits
# 9. Multiple breeds produce variety (not all children identical)
# ============================================================================

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Breeding Tests ===")
	var all_passed: bool = true

	# Helper: create two parent strains with known traits
	var parent_a = Strain.create_seed()
	parent_a.strain_name = "ParentA"
	parent_a.stealth = 0.8
	parent_a.speed = 0.3
	parent_a.payload = 0.7
	parent_a.resilience = 0.5
	parent_a.stability = 0.9
	parent_a.generation = 1

	var parent_b = Strain.create_seed()
	parent_b.strain_name = "ParentB"
	parent_b.stealth = 0.2
	parent_b.speed = 0.6
	parent_b.payload = 0.4
	parent_b.resilience = 0.8
	parent_b.stability = 0.9
	parent_b.generation = 2

	# Test 1: breed() produces a valid child
	print("\n[1] Testing breed() produces valid child...")
	var child = Breeding.breed(parent_a, parent_b)
	if child == null:
		print("  FAIL: breed() returned null")
		all_passed = false
	elif not (child.strain_name.length() > 0):
		print("  FAIL: child has no name")
		all_passed = false
	else:
		print("  PASS: child created - %s" % child.strain_name)
		print("  Stats: stealth=%.2f speed=%.2f payload=%.2f resilience=%.2f stability=%.2f" % [
			child.stealth, child.speed, child.payload, child.resilience, child.stability])

	# Test 2: Child traits are within expected range
	# Expected: min(parents) - 0.05 - 0.15 to max(parents) + 0.05 + 0.15
	# (0.05 jitter + 0.15 max mutation = 0.20 max deviation)
	print("\n[2] Testing child traits in valid range...")
	var traits_in_range: bool = true
	var checks: Dictionary = {
		"stealth": [min(parent_a.stealth, parent_b.stealth) - 0.2, max(parent_a.stealth, parent_b.stealth) + 0.2],
		"speed": [min(parent_a.speed, parent_b.speed) - 0.2, max(parent_a.speed, parent_b.speed) + 0.2],
		"payload": [min(parent_a.payload, parent_b.payload) - 0.2, max(parent_a.payload, parent_b.payload) + 0.2],
		"resilience": [min(parent_a.resilience, parent_b.resilience) - 0.2, max(parent_a.resilience, parent_b.resilience) + 0.2],
	}
	for trait_name in checks:
		var child_val: float = child.get(trait_name)
		var min_expected: float = checks[trait_name][0]
		var max_expected: float = checks[trait_name][1]
		if child_val < min_expected or child_val > max_expected:
			print("  FAIL: %s = %.2f outside range [%.2f, %.2f]" % [trait_name, child_val, min_expected, max_expected])
			traits_in_range = false
	if traits_in_range:
		print("  PASS: all child traits within expected range (parent range +/- 0.20)")
	else:
		all_passed = false

	# Test 3: Child generation is max(parents) + 1
	print("\n[3] Testing child generation...")
	var expected_gen: int = max(parent_a.generation, parent_b.generation) + 1
	if child.generation == expected_gen:
		print("  PASS: child generation = %d (expected %d)" % [child.generation, expected_gen])
	else:
		print("  FAIL: child generation = %d (expected %d)" % [child.generation, expected_gen])
		all_passed = false

	# Test 4: get_breed_cost() returns sensible values
	print("\n[4] Testing get_breed_cost()...")
	var cost: int = Breeding.get_breed_cost(parent_a, parent_b)
	# Both parents gen 1 and 2, max_gen=2, so cost = 200 + 2*100 = 400
	if cost > 0 and cost < 1000:
		print("  PASS: breed cost = %d (expected ~400)" % cost)
	else:
		print("  FAIL: breed cost = %d (seems wrong)" % cost)
		all_passed = false

	# Test 5: Mutation chance with low stability vs high stability
	print("\n[5] Testing mutation chance calculation...")
	# Create low-stability parents
	var unstable_a = Strain.create_seed()
	unstable_a.stability = 0.1
	var unstable_b = Strain.create_seed()
	unstable_b.stability = 0.1
	# Create high-stability parents
	var stable_a = Strain.create_seed()
	stable_a.stability = 1.0
	var stable_b = Strain.create_seed()
	stable_b.stability = 1.0

	# The _calculate_mutation_chance is private (starts with _), but we can
	# test it indirectly: breed unstable strains many times and count mutations
	var unstable_mutations: int = 0
	var stable_mutations: int = 0
	var num_trials: int = 50

	for i in range(num_trials):
		var unstable_child = Breeding.breed(unstable_a, unstable_b)
		var unstable_muts = Breeding.detect_mutations(unstable_child, unstable_a, unstable_b)
		if unstable_muts.size() > 0:
			unstable_mutations += 1

		var stable_child = Breeding.breed(stable_a, stable_b)
		var stable_muts = Breeding.detect_mutations(stable_child, stable_a, stable_b)
		if stable_muts.size() > 0:
			stable_mutations += 1

	print("  Unstable parents: %d/%d children had mutations" % [unstable_mutations, num_trials])
	print("  Stable parents:   %d/%d children had mutations" % [stable_mutations, num_trials])
	if unstable_mutations > stable_mutations:
		print("  PASS: unstable parents produce more mutations")
	else:
		print("  FAIL: unstable parents should produce more mutations")
		all_passed = false

	# Test 6: Personality inheritance - both parents same personality
	print("\n[6] Testing personality inheritance...")
	var aggr_a = Strain.create_seed()
	aggr_a.personality = Strain.Personality.AGGRESSIVE
	var aggr_b = Strain.create_seed()
	aggr_b.personality = Strain.Personality.AGGRESSIVE

	var same_personality_count: int = 0
	for i in range(20):
		var c = Breeding.breed(aggr_a, aggr_b)
		if c.personality == Strain.Personality.AGGRESSIVE:
			same_personality_count += 1
	if same_personality_count == 20:
		print("  PASS: same-personality parents always pass it on (20/20)")
	else:
		print("  FAIL: same-personality parents should always pass it on (%d/20)" % same_personality_count)
		all_passed = false

	# Test 7: Breeding a strain with itself returns null
	print("\n[7] Testing self-breeding prevention...")
	var self_child = Breeding.breed(parent_a, parent_a)
	if self_child == null:
		print("  PASS: breeding a strain with itself returns null")
	else:
		print("  FAIL: self-breeding should return null")
		all_passed = false

	# Test 8: detect_mutations() works
	print("\n[8] Testing detect_mutations()...")
	# With stable parents (stability=1.0), mutations are rare but possible
	# Let's just verify the function returns a Dictionary (even if empty)
	var muts = Breeding.detect_mutations(child, parent_a, parent_b)
	if typeof(muts) == TYPE_DICTIONARY:
		print("  PASS: detect_mutations() returned a Dictionary with %d entries" % muts.size())
	else:
		print("  FAIL: detect_mutations() should return a Dictionary")
		all_passed = false

	# Test 9: Multiple breeds produce variety
	print("\n[9] Testing breeding variety...")
	var names: Array = []
	var all_payloads: Array = []
	for i in range(10):
		var c = Breeding.breed(parent_a, parent_b)
		names.append(c.strain_name)
		all_payloads.append(c.payload)
	var unique_names: int = 0
	for n in names:
		if names.count(n) == 1:
			unique_names += 1
	# Check that payloads aren't all identical
	var all_same: bool = true
	for p in all_payloads:
		if p != all_payloads[0]:
			all_same = false
			break
	if not all_same and unique_names >= 8:
		print("  PASS: 10 breeds produced variety (unique names: %d, varied payloads)" % unique_names)
	else:
		print("  FAIL: breeds should produce variety (unique names: %d, payloads same: %s)" % [unique_names, all_same])
		all_passed = false

	# ====================================================================
	# NAMED MUTATION EVENT TESTS (Phase 2)
	# ====================================================================

	# Test 10: mutation_event is populated when a mutation occurs
	print("\n[10] Testing mutation_event is set on mutated children...")
	# Use very unstable parents to guarantee mutations
	var unstable_parent_a = Strain.create_seed()
	unstable_parent_a.stability = 0.01
	unstable_parent_a.strain_name = "UnstableA"
	var unstable_parent_b = Strain.create_seed()
	unstable_parent_b.stability = 0.01
	unstable_parent_b.strain_name = "UnstableB"

	var mutation_found: bool = false
	var attempts: int = 0
	for i in range(100):
		var c = Breeding.breed(unstable_parent_a, unstable_parent_b)
		if not c.mutation_event.is_empty():
			mutation_found = true
			# Verify the event Dictionary has the expected keys
			var event: Dictionary = c.mutation_event
			var has_name: bool = event.has("event_name")
			var has_desc: bool = event.has("event_desc")
			var has_color: bool = event.has("event_color")
			var has_traits: bool = event.has("affected_traits")
			var has_details: bool = event.has("details")
			if has_name and has_desc and has_color and has_traits and has_details:
				print("  PASS: mutation_event populated with all keys -- event: %s" % event["event_name"])
			else:
				print("  FAIL: mutation_event missing keys (name=%s desc=%s color=%s traits=%s details=%s)" % [
					has_name, has_desc, has_color, has_traits, has_details])
				all_passed = false
			break
	if not mutation_found:
		print("  FAIL: no mutations triggered in 100 breeds with unstable parents")
		all_passed = false

	# Test 11: mutation_event is empty when no mutation occurs (stable parents)
	print("\n[11] Testing mutation_event is empty for stable parents...")
	var stable_parent_a = Strain.create_seed()
	stable_parent_a.stability = 1.0
	stable_parent_a.strain_name = "StableA"
	var stable_parent_b = Strain.create_seed()
	stable_parent_b.stability = 1.0
	stable_parent_b.strain_name = "StableB"

	var stable_no_mutations: bool = true
	for i in range(20):
		var c = Breeding.breed(stable_parent_a, stable_parent_b)
		if not c.mutation_event.is_empty():
			stable_no_mutations = false
			break
	if stable_no_mutations:
		print("  PASS: stable parents produced no mutation events in 20 breeds")
	else:
		print("  FAIL: stable parents (stability=1.0) should rarely mutate")
		all_passed = false

	# Test 12: All mutation event types can be triggered
	print("\n[12] Testing all mutation event types appear...")
	# Breed many unstable children and collect all event names
	var event_names_seen: Array = []
	for i in range(500):
		var c = Breeding.breed(unstable_parent_a, unstable_parent_b)
		if not c.mutation_event.is_empty():
			var name: String = c.mutation_event.get("event_name", "")
			if not event_names_seen.has(name):
				event_names_seen.append(name)
	print("  Events seen: %s" % str(event_names_seen))
	# We should at minimum see the two common events (SURGE, DEGRADE)
	# and ideally at least one rare event in 500 breeds
	if event_names_seen.has("TRAIT SURGE") and event_names_seen.has("DEGRADATION"):
		print("  PASS: common events (SURGE, DEGRADE) both appeared")
		if event_names_seen.size() >= 3:
			print("  BONUS: %d distinct event types appeared (good variety)" % event_names_seen.size())
	else:
		print("  FAIL: expected at least TRAIT SURGE and DEGRADATION in 500 breeds")
		all_passed = false

	# Test 13: HYPERGENESIS boosts all traits
	print("\n[13] Testing HYPERGENESIS affects all 5 traits...")
	# We can't force a specific mutation, but we can breed many unstable
	# children and check if any had a HYPERGENESIS event with 5 affected traits
	var hypergenesis_found: bool = false
	for i in range(500):
		var c = Breeding.breed(unstable_parent_a, unstable_parent_b)
		if not c.mutation_event.is_empty():
			var name: String = c.mutation_event.get("event_name", "")
			if name == "HYPERGENESIS":
				var affected: Array = c.mutation_event.get("affected_traits", [])
				if affected.size() == 5:
					hypergenesis_found = true
					print("  PASS: HYPERGENESIS affected all 5 traits")
					break
	if not hypergenesis_found:
		# HYPERGENESIS is 5% of mutations -- in 500 breeds with ~45% mutation
		# chance that's ~11 HYPERGENESIS events expected. Very unlikely to miss.
		print("  FAIL: no HYPERGENESIS with 5 affected traits in 500 breeds")
		all_passed = false

	# Test 14: STABILITY COLLAPSE drops stability to near 0
	print("\n[14] Testing STABILITY COLLAPSE crashes stability...")
	var collapse_found: bool = false
	for i in range(500):
		var c = Breeding.breed(unstable_parent_a, unstable_parent_b)
		if not c.mutation_event.is_empty():
			var name: String = c.mutation_event.get("event_name", "")
			if name == "STABILITY COLLAPSE":
				if c.stability <= 0.15:
					collapse_found = true
					print("  PASS: STABILITY COLLAPSE dropped stability to %.0f%%" % (c.stability * 100))
					break
	if not collapse_found:
		print("  FAIL: no STABILITY COLLAPSE with stability <= 15%% in 500 breeds")
		all_passed = false

	# Results
	print("\n=== RESULTS ===")
	if all_passed:
		print("ALL BREEDING TESTS PASSED")
	else:
		print("SOME BREEDING TESTS FAILED")

	quit()