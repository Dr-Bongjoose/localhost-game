# ============================================================================
# test_codex.gd - Verification that codex.gd works correctly
# ============================================================================
# Tests:
# 1. Adding a strain to the codex works
# 2. Adding the same strain twice doesn't create a duplicate
# 3. Rarity calculation produces correct tiers
# 4. Breed count tracking works
# 5. get_summary() returns readable text
# 6. get_entry_details() returns full strain info
# 7. get_count_by_rarity() counts correctly
# 8. Sorting by rarity works
# 9. clear() empties the codex
# ============================================================================

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Codex Tests ===")
	var all_passed: bool = true

	# Create a fresh codex
	var c = Codex.new()

	# Test 1: Add a strain
	print("\n[1] Testing add_strain()...")
	var seed_strain = Strain.create_seed()
	var idx = c.add_strain(seed_strain)
	if idx == 0 and c.get_count() == 1:
		print("  PASS: strain added, index=%d, count=%d" % [idx, c.get_count()])
	else:
		print("  FAIL: expected index=0 count=1, got index=%d count=%d" % [idx, c.get_count()])
		all_passed = false

	# Test 2: Adding same strain again doesn't duplicate
	print("\n[2] Testing duplicate prevention...")
	var idx2 = c.add_strain(seed_strain)
	if idx2 == 0 and c.get_count() == 1:
		print("  PASS: duplicate not added (count still %d)" % c.get_count())
	else:
		print("  FAIL: duplicate was added (count=%d)" % c.get_count())
		all_passed = false

	# Test 3: Rarity calculation
	print("\n[3] Testing rarity calculation...")

	# Create strains with known trait scores
	var weak_strain = Strain.new()
	weak_strain.stealth = 0.1
	weak_strain.speed = 0.1
	weak_strain.payload = 0.1
	weak_strain.resilience = 0.1
	weak_strain.stability = 0.1
	# Total: 0.5 -> COMMON
	weak_strain.personality = Strain.Personality.NONE
	weak_strain.generation = 1
	weak_strain.strain_name = "WeakStrain"

	var mid_strain = Strain.new()
	mid_strain.stealth = 0.5
	mid_strain.speed = 0.5
	mid_strain.payload = 0.5
	mid_strain.resilience = 0.5
	mid_strain.stability = 0.5
	# Total: 2.5 -> UNCOMMON
	mid_strain.personality = Strain.Personality.NONE
	mid_strain.generation = 1
	mid_strain.strain_name = "MidStrain"

	var strong_strain = Strain.new()
	strong_strain.stealth = 0.7
	strong_strain.speed = 0.7
	strong_strain.payload = 0.7
	strong_strain.resilience = 0.7
	strong_strain.stability = 0.7
	# Total: 3.5 + 0.3 (personality) = 3.8 -> MYTHIC (but we need to test boundaries)
	strong_strain.personality = Strain.Personality.AGGRESSIVE
	strong_strain.generation = 1
	strong_strain.strain_name = "StrongStrain"

	var weak_rarity = c.calculate_rarity(weak_strain)
	var mid_rarity = c.calculate_rarity(mid_strain)
	var strong_rarity = c.calculate_rarity(strong_strain)

	if weak_rarity == Codex.Rarity.COMMON:
		print("  PASS: weak strain is Common (score=0.5)")
	else:
		print("  FAIL: weak strain should be Common, got %s" % c.get_rarity_name(weak_rarity))
		all_passed = false

	# mid strain: 0.5*5 = 2.5 -> COMMON (at the boundary, < 2.5 is false, so it's
	# actually >= 2.5 which means COMMON since 2.5 is not < 2.5... wait, 2.5 < 2.5
	# is false, so it falls through to UNCOMMON)
	# Actually: 2.5 is not < 2.5, so it's not COMMON. 2.5 < 3.0 is true -> UNCOMMON
	if mid_rarity == Codex.Rarity.UNCOMMON:
		print("  PASS: mid strain is Uncommon (score=2.5, boundary)")
	else:
		print("  FAIL: mid strain should be Uncommon, got %s" % c.get_rarity_name(mid_rarity))
		all_passed = false

	# Strong strain: 0.7*5=3.5 + 0.3 personality = 3.8 -> LEGENDARY (3.5 <= 3.8 < 4.0)
	if strong_rarity == Codex.Rarity.LEGENDARY:
		print("  PASS: strong+personality strain is Legendary (score=3.8)")
	else:
		print("  FAIL: strong+personality should be Legendary, got %s" % c.get_rarity_name(strong_rarity))
		all_passed = false

	# Test 4: Breed count tracking
	print("\n[4] Testing breed count tracking...")
	c.add_strain(mid_strain)
	c.increment_breed_count(seed_strain)
	c.increment_breed_count(seed_strain)
	c.increment_breed_count(mid_strain)

	# Find the seed strain entry and check its breed count
	var seed_breed_count: int = -1
	for i in range(c.get_count()):
		if c.entries[i]["strain"].strain_name == seed_strain.strain_name:
			seed_breed_count = c.entries[i]["breed_count"]
			break

	if seed_breed_count == 2:
		print("  PASS: seed strain breed count = 2")
	else:
		print("  FAIL: seed breed count should be 2, got %d" % seed_breed_count)
		all_passed = false

	# Test 5: get_summary()
	print("\n[5] Testing get_summary()...")
	var summary = c.get_summary()
	if summary.contains("CODEX") and summary.contains("discovered"):
		print("  PASS: summary is readable")
		print("  ", summary.replace("\n", "\n  "))
	else:
		print("  FAIL: summary is malformed: '%s'" % summary)
		all_passed = false

	# Test 6: get_entry_details()
	print("\n[6] Testing get_entry_details()...")
	var details = c.get_entry_details(0)
	if details.contains(seed_strain.strain_name) and details.contains("Rarity:"):
		print("  PASS: entry details contain name and rarity")
		print("  ", details.replace("\n", "\n  "))
	else:
		print("  FAIL: entry details missing info: '%s'" % details)
		all_passed = false

	# Test 7: get_count_by_rarity()
	print("\n[7] Testing get_count_by_rarity()...")
	# In the codex now: seed_strain (score 2.4 -> COMMON), mid_strain (score 2.5 -> UNCOMMON)
	# seed_strain: 0.4+0.5+0.2+0.5+0.8 = 2.4, no personality, gen 1 -> 2.4 < 2.5 -> COMMON
	# mid_strain: 0.5*5 = 2.5, no personality, gen 1 -> 2.5 is NOT < 2.5 -> UNCOMMON
	var common_count = c.get_count_by_rarity(Codex.Rarity.COMMON)
	var uncommon_count = c.get_count_by_rarity(Codex.Rarity.UNCOMMON)
	if common_count == 1 and uncommon_count == 1:
		print("  PASS: Common=%d, Uncommon=%d" % [common_count, uncommon_count])
	else:
		print("  FAIL: expected Common=1 Uncommon=1, got Common=%d Uncommon=%d" % [common_count, uncommon_count])
		all_passed = false

	# Test 8: Sorting by rarity
	print("\n[8] Testing get_entries_sorted_by_rarity()...")
	c.add_strain(strong_strain)
	# Now codex has: seed (Uncommon), mid (Uncommon), strong (Mythic)
	var sorted = c.get_entries_sorted_by_rarity()
	if sorted.size() >= 3:
		# First entry should be highest rarity (Mythic for strong_strain)
		var first_rarity = sorted[0]["rarity"]
		var last_rarity = sorted[sorted.size() - 1]["rarity"]
		if first_rarity >= last_rarity:
			print("  PASS: sorted by rarity descending (first=%s, last=%s, count=%d)" % [
				c.get_rarity_name(first_rarity), c.get_rarity_name(last_rarity), sorted.size()])
		else:
			print("  FAIL: first entry should be higher rarity than last")
			all_passed = false
	else:
		print("  FAIL: expected at least 3 entries, got %d" % sorted.size())
		all_passed = false

	# Test 9: clear()
	print("\n[9] Testing clear()...")
	c.clear()
	if c.get_count() == 0 and c.entries.is_empty():
		print("  PASS: codex cleared (count=%d)" % c.get_count())
	else:
		print("  FAIL: codex not empty after clear (count=%d)" % c.get_count())
		all_passed = false

	# Results
	print("\n=== RESULTS ===")
	if all_passed:
		print("ALL CODEX TESTS PASSED")
	else:
		print("SOME CODEX TESTS FAILED")

	quit()