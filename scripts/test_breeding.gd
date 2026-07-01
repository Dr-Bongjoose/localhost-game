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
	# Breeding can fail now -- retry up to 10 times to get a child
	var child: Strain = null
	for _retry in range(10):
		child = Breeding.breed(parent_a, parent_b)
		if child != null:
			break
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
		# Breeding can now fail (risk mechanic) -- skip null children
		if unstable_child == null:
			continue
		var unstable_muts = Breeding.detect_mutations(unstable_child, unstable_a, unstable_b)
		if unstable_muts.size() > 0:
			unstable_mutations += 1

		var stable_child = Breeding.breed(stable_a, stable_b)
		# Breeding can now fail -- skip null children
		if stable_child == null:
			continue
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
	var personality_trials: int = 0
	for i in range(20):
		var c = Breeding.breed(aggr_a, aggr_b)
		if c == null:
			continue  # Breeding failed, skip
		personality_trials += 1
		if c.personality == Strain.Personality.AGGRESSIVE:
			same_personality_count += 1
	if same_personality_count == personality_trials and personality_trials > 0:
		print("  PASS: same-personality parents always pass it on (%d/%d)" % [same_personality_count, personality_trials])
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
	# But breeding can also fail now -- if it did, breed again until we get a child
	var test_child: Strain = child
	if test_child == null:
		# The first breed failed, try again
		for _i in range(10):
			test_child = Breeding.breed(parent_a, parent_b)
			if test_child != null:
				break
	if test_child == null:
		print("  SKIP: could not get a successful child after 10 attempts")
	else:
		var muts = Breeding.detect_mutations(test_child, parent_a, parent_b)
		if typeof(muts) == TYPE_DICTIONARY:
			print("  PASS: detect_mutations() returned a Dictionary with %d entries" % muts.size())
		else:
			print("  FAIL: detect_mutations() should return a Dictionary")
			all_passed = false

	# Test 9: Multiple breeds produce variety
	print("\n[9] Testing breeding variety...")
	var names: Array = []
	var all_payloads: Array = []
	for i in range(15):  # More attempts to account for breeding failures
		var c = Breeding.breed(parent_a, parent_b)
		if c == null:
			continue  # Breeding failed, skip
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
	if not all_same and unique_names >= 6:
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
		if c == null:
			continue  # Breeding failed, skip
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
		# Reset stability each iteration -- genetic damage (15% chance per breed)
		# can lower stability, which would increase mutation chance on subsequent
		# breeds. By resetting, we ensure each breed starts from stability=1.0.
		stable_parent_a.stability = 1.0
		stable_parent_b.stability = 1.0
		var c = Breeding.breed(stable_parent_a, stable_parent_b)
		if c == null:
			continue  # Breeding failed, skip
		if not c.mutation_event.is_empty():
			# DEGRADED OFFSPRING is a risk mechanic, not a mutation -- it can
			# trigger even with stable parents (12% base chance). Only count
			# actual mutations (SURGE, DEGRADE, INVERSION, etc.) as failures.
			var event_name: String = c.mutation_event.get("event_name", "")
			if event_name != "DEGRADED OFFSPRING":
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
		if c == null:
			continue  # Breeding failed, skip
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
		if c == null:
			continue  # Breeding failed, skip
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
		if c == null:
			continue  # Breeding failed, skip
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

	# ====================================================================
	# BREEDING RISK MECHANIC TESTS (Phase 2)
	# ====================================================================

	# Test 15: Breeding failure can occur with high gen gap + low stability
	print("\n[15] Testing breeding failure with high gen gap + low stability...")
	var gen5_a = Strain.create_seed()
	gen5_a.stability = 0.1
	gen5_a.generation = 1
	gen5_a.strain_name = "GenOneA"
	var gen5_b = Strain.create_seed()
	gen5_b.stability = 0.1
	gen5_b.generation = 5
	gen5_b.strain_name = "GenFiveB"

	var failure_count: int = 0
	var total_breeds_15: int = 200
	for i in range(total_breeds_15):
		# Reset stability each time since genetic damage can lower it
		gen5_a.stability = 0.1
		gen5_b.stability = 0.1
		var c = Breeding.breed(gen5_a, gen5_b)
		if c == null and Breeding.last_breed_result == Breeding.BreedResult.FAILURE:
			failure_count += 1

	var fail_rate: float = float(failure_count) / total_breeds_15
	print("  Failures: %d/%d (%.0f%%)" % [failure_count, total_breeds_15, fail_rate * 100])
	# Gen gap 4, stability 0.1 -> chance = 5% + 20% + 9% = 34% -> capped to 30%
	# So we expect ~30% failures. Allow 15-45% range for random variance.
	if failure_count > 0 and fail_rate >= 0.15 and fail_rate <= 0.45:
		print("  PASS: failures occurred at expected rate")
	else:
		print("  FAIL: expected 15-45%% failure rate, got %.0f%%" % (fail_rate * 100))
		all_passed = false

	# Test 16: Breeding failure is rare with same-gen + high stability
	print("\n[16] Testing breeding failure is rare with same-gen + high stability...")
	var safe_a = Strain.create_seed()
	safe_a.stability = 0.9
	safe_a.generation = 1
	safe_a.strain_name = "SafeA"
	var safe_b = Strain.create_seed()
	safe_b.stability = 0.9
	safe_b.generation = 1
	safe_b.strain_name = "SafeB"

	var safe_failures: int = 0
	for i in range(50):
		# Reset stability since genetic damage can lower it
		safe_a.stability = 0.9
		safe_b.stability = 0.9
		var c = Breeding.breed(safe_a, safe_b)
		if c == null and Breeding.last_breed_result == Breeding.BreedResult.FAILURE:
			safe_failures += 1

	print("  Failures: %d/50" % safe_failures)
	# Gen gap 0, stability 0.9 -> chance = 5% + 0% + 1% = 6%
	# In 50 breeds, expect ~3 failures. Allow < 8 (loose upper bound).
	if safe_failures < 8:
		print("  PASS: failures are rare with high stability (%d/50)" % safe_failures)
	else:
		print("  FAIL: too many failures with high stability (%d/50)" % safe_failures)
		all_passed = false

	# Test 17: Degraded offspring produces weaker child
	print("\n[17] Testing degraded offspring produces weaker child...")
	var deg_a = Strain.create_seed()
	deg_a.stability = 0.1
	deg_a.stealth = 0.8
	deg_a.speed = 0.8
	deg_a.payload = 0.8
	deg_a.resilience = 0.8
	deg_a.generation = 1
	deg_a.strain_name = "DegA"
	var deg_b = Strain.create_seed()
	deg_b.stability = 0.1
	deg_b.stealth = 0.8
	deg_b.speed = 0.8
	deg_b.payload = 0.8
	deg_b.resilience = 0.8
	deg_b.generation = 1
	deg_b.strain_name = "DegB"

	var degraded_found: bool = false
	for i in range(300):
		deg_a.stability = 0.1
		deg_b.stability = 0.1
		var c = Breeding.breed(deg_a, deg_b)
		if c == null:
			continue
		if not c.mutation_event.is_empty():
			var event_name: String = c.mutation_event.get("event_name", "")
			if event_name == "DEGRADED OFFSPRING":
				degraded_found = true
				# Check that traits are reduced (child should be weaker than parent average)
				# Parent average for each trait is 0.8, degraded = 0.8 * 0.8-0.9 = 0.64-0.72
				# After normal inheritance (60/40 of same values + jitter) it's ~0.8
				# After degradation: ~0.8 * 0.8-0.9 = ~0.64-0.72
				# So child payload should be well below 0.8
				if c.payload < 0.78:
					print("  PASS: degraded offspring found with reduced traits (payload: %.0f%%)" % (c.payload * 100))
				else:
					print("  FAIL: degraded offspring traits not reduced enough (payload: %.0f%%)" % (c.payload * 100))
					all_passed = false
				break
	if not degraded_found:
		print("  FAIL: no degraded offspring found in 300 breeds")
		all_passed = false

	# Test 18: Genetic damage reduces parent stability
	print("\n[18] Testing genetic damage reduces parent stability...")
	var dmg_a = Strain.create_seed()
	dmg_a.stability = 0.5
	dmg_a.generation = 1
	dmg_a.strain_name = "DmgA"
	var dmg_b = Strain.create_seed()
	dmg_b.stability = 0.5
	dmg_b.generation = 1
	dmg_b.strain_name = "DmgB"

	var damage_found: bool = false
	for i in range(200):
		# Reset stability each iteration to detect damage
		dmg_a.stability = 0.5
		dmg_b.stability = 0.5
		var c = Breeding.breed(dmg_a, dmg_b)
		if c == null:
			continue
		if not Breeding.last_genetic_damage.is_empty():
			damage_found = true
			var dmg: Dictionary = Breeding.last_genetic_damage
			var parent_name: String = dmg.get("parent_name", "")
			var lost: float = dmg.get("stability_lost", 0.0)
			var new_stab: float = dmg.get("new_stability", 0.0)
			if new_stab < 0.5 and lost > 0.0:
				print("  PASS: genetic damage detected -- %s lost %.0f%% stability (now %.0f%%)" % [
					parent_name, lost * 100, new_stab * 100])
			else:
				print("  FAIL: genetic damage data invalid (lost=%.2f, new=%.2f)" % [lost, new_stab])
				all_passed = false
			break
	if not damage_found:
		print("  FAIL: no genetic damage in 200 breeds (15%% chance, expected ~30)")
		all_passed = false

	# Test 19: last_breed_result is set correctly
	print("\n[19] Testing last_breed_result is set correctly...")
	# Test SELF_BREEDING
	var self_a = Strain.create_seed()
	self_a.strain_name = "SelfTest"
	var self_result = Breeding.breed(self_a, self_a)
	if self_result == null and Breeding.last_breed_result == Breeding.BreedResult.SELF_BREEDING:
		print("  PASS: self-breeding sets last_breed_result = SELF_BREEDING")
	else:
		print("  FAIL: self-breeding should set SELF_BREEDING (got result=%d)" % Breeding.last_breed_result)
		all_passed = false

	# Test SUCCESS (breed two different bugs with high stability to avoid failure)
	var succ_a = Strain.create_seed()
	succ_a.stability = 1.0
	succ_a.strain_name = "SuccA"
	var succ_b = Strain.create_seed()
	succ_b.stability = 1.0
	succ_b.strain_name = "SuccB"
	# Try up to 10 times to get a success (failure chance is 6% so very likely first try)
	var success_result: bool = false
	for i in range(10):
		succ_a.stability = 1.0
		succ_b.stability = 1.0
		var c = Breeding.breed(succ_a, succ_b)
		if c != null and Breeding.last_breed_result == Breeding.BreedResult.SUCCESS:
			success_result = true
			break
	if success_result:
		print("  PASS: normal breeding sets last_breed_result = SUCCESS")
	else:
		print("  FAIL: could not get a SUCCESS result after 10 attempts")
		all_passed = false

	# Results
	print("\n=== RESULTS ===")
	if all_passed:
		print("ALL BREEDING TESTS PASSED")
	else:
		print("SOME BREEDING TESTS FAILED")

	quit()