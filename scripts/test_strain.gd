# ============================================================================
# test_strain.gd - Quick verification that strain.gd works correctly
# ============================================================================
# This is a temporary test script. We run it headless to verify:
# 1. create_seed() produces a valid strain
# 2. create_random() produces valid random strains
# 3. get_income_per_second() returns sensible numbers
# 4. get_heat_per_second() returns sensible numbers
# 5. get_summary() produces readable text

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Strain Tests ===")
	var all_passed: bool = true

	# Test 1: Seed strain
	print("\n[1] Testing create_seed()...")
	var seed_strain = Strain.create_seed()
	if seed_strain == null:
		print("  FAIL: create_seed() returned null")
		all_passed = false
	elif seed_strain.strain_name != "Seed-001":
		print("  FAIL: seed name is '%s' (expected 'Seed-001')" % seed_strain.strain_name)
		all_passed = false
	elif not (seed_strain.payload > 0.0 and seed_strain.payload < 1.0):
		print("  FAIL: seed payload out of range: %f" % seed_strain.payload)
		all_passed = false
	else:
		print("  PASS: seed strain created - %s" % seed_strain.strain_name)
		print("  Stats: stealth=%.2f speed=%.2f payload=%.2f resilience=%.2f stability=%.2f" % [
			seed_strain.stealth, seed_strain.speed, seed_strain.payload,
			seed_strain.resilience, seed_strain.stability])

	# Test 2: Random strain
	print("\n[2] Testing create_random()...")
	var random_strain = Strain.create_random(1, "Worm")
	if random_strain == null:
		print("  FAIL: create_random() returned null")
		all_passed = false
	elif not random_strain.strain_name.begins_with("Worm-"):
		print("  FAIL: random strain name doesn't start with 'Worm-': '%s'" % random_strain.strain_name)
		all_passed = false
	else:
		print("  PASS: random strain created - %s" % random_strain.strain_name)

	# Test 3: Income calculation
	print("\n[3] Testing get_income_per_second()...")
	var income = seed_strain.get_income_per_second()
	# Seed: payload=0.3, speed=0.5 -> 0.3 * 10.0 * (0.5 + 0.5) = 3.0
	if income < 0.0:
		print("  FAIL: income is negative: %f" % income)
		all_passed = false
	elif income > 100.0:
		print("  FAIL: income seems too high: %f" % income)
		all_passed = false
	else:
		print("  PASS: seed income = %.2f data/sec (expected ~3.0)" % income)

	# Test 4: Heat generation
	print("\n[4] Testing get_heat_per_second()...")
	var heat = seed_strain.get_heat_per_second()
	if heat < 0.0:
		print("  FAIL: heat is negative: %f" % heat)
		all_passed = false
	elif heat > 10.0:
		print("  FAIL: heat seems too high: %f" % heat)
		all_passed = false
	else:
		print("  PASS: seed heat = %.2f/sec (expected ~0.3)" % heat)

	# Test 5: Summary text
	print("\n[5] Testing get_summary()...")
	var summary = seed_strain.get_summary()
	if summary.is_empty():
		print("  FAIL: summary is empty")
		all_passed = false
	elif not summary.contains("Seed-001"):
		print("  FAIL: summary doesn't contain strain name")
		all_passed = false
	else:
		print("  PASS: summary contains strain name and stats")
		print("  Summary:")
		for line in summary.split("\n"):
			print("    ", line)

	# Test 6: Personality label
	print("\n[6] Testing get_personality_label()...")
	var label = seed_strain.get_personality_label()
	if label != "Basic":
		print("  FAIL: seed personality label is '%s' (expected 'Basic')" % label)
		all_passed = false
	else:
		print("  PASS: seed personality = '%s'" % label)

	# Test 7: Multiple random strains have variety
	print("\n[7] Testing random strain variety...")
	var names: Array = []
	var all_valid: bool = true
	for i in range(10):
		var s = Strain.create_random(1, "Worm")
		names.append(s.strain_name)
		if not (s.stealth >= 0.1 and s.stealth <= 0.9):
			print("  FAIL: stealth out of range: %f" % s.stealth)
			all_valid = false
	if all_valid:
		print("  PASS: created 10 random strains, all traits in valid range")
		print("  Names: ", names)

	# Results
	print("\n=== RESULTS ===")
	if all_passed and all_valid:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")

	quit()