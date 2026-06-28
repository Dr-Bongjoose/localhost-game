# ============================================================================
# test_zone.gd - Verification that zone.gd works correctly
# ============================================================================
# Tests:
# 1. Zone creation by type produces correct properties
# 2. Deploy/recall mechanics work
# 3. Capacity limits are enforced
# 4. Zone income calculation is correct (base income * data_value)
# 5. Zone heat accumulates from deployed strains
# 6. Raid check triggers when heat exceeds threshold
# 7. Resilience affects survival during raids
# 8. get_summary() and get_short_status() return readable text
# 9. Heat decays when zone is empty
# 10. Dark Web zones have randomized properties
# ============================================================================

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Zone Tests ===")
	var all_passed: bool = true

	# Test 1: Zone creation produces correct properties
	print("\n[1] Testing zone creation by type...")
	var consumer = Zone.create(Zone.ZoneType.CONSUMER)
	var corporate = Zone.create(Zone.ZoneType.CORPORATE)
	var gov = Zone.create(Zone.ZoneType.GOVERNMENT)

	if consumer.zone_name == "Consumer Network" and consumer.data_value == 1.5:
		print("  PASS: Consumer Network created correctly (payout=1.5x)")
	else:
		print("  FAIL: Consumer Network properties wrong")
		all_passed = false

	if corporate.data_value == 2.5 and corporate.detection_rate == 1.0:
		print("  PASS: Corporate Server created correctly (payout=2.5x, det=1.0)")
	else:
		print("  FAIL: Corporate Server properties wrong")
		all_passed = false

	if gov.data_value == 4.0 and gov.detection_threshold == 30.0 and gov.capacity == 1:
		print("  PASS: Government Network created correctly (payout=4.0x, threshold=30, cap=1)")
	else:
		print("  FAIL: Government Network properties wrong")
		all_passed = false

	# Test 2: Deploy and recall
	print("\n[2] Testing deploy/recall mechanics...")
	var strain1 = Strain.create_seed()
	var strain2 = Strain.create_random(1, "Worm")

	if consumer.deploy(strain1):
		print("  PASS: strain1 deployed to Consumer Network")
	else:
		print("  FAIL: deploy returned false")
		all_passed = false

	if consumer.has_strain(strain1):
		print("  PASS: has_strain() confirms deployment")
	else:
		print("  FAIL: has_strain() didn't find deployed strain")
		all_passed = false

	if consumer.recall(strain1):
		print("  PASS: strain1 recalled successfully")
	else:
		print("  FAIL: recall returned false")
		all_passed = false

	if not consumer.has_strain(strain1):
		print("  PASS: strain1 no longer in zone after recall")
	else:
		print("  FAIL: strain1 still in zone after recall")
		all_passed = false

	# Test 3: Capacity limits
	print("\n[3] Testing capacity limits...")
	# Government has capacity 1
	gov.deploy(strain1)
	if not gov.deploy(strain2):
		print("  PASS: Government Network (cap=1) rejected second strain")
	else:
		print("  FAIL: Government Network accepted second strain over capacity")
		all_passed = false

	if gov.is_full():
		print("  PASS: is_full() returns true when at capacity")
	else:
		print("  FAIL: is_full() returned false at capacity")
		all_passed = false

	if gov.get_free_slots() == 0:
		print("  PASS: get_free_slots() returns 0 when full")
	else:
		print("  FAIL: get_free_slots() returned %d, expected 0" % gov.get_free_slots())
		all_passed = false

	# Clean up
	gov.recall(strain1)

	# Test 4: Zone income calculation
	print("\n[4] Testing zone income calculation...")
	consumer.deploy(strain1)
	var base_income = strain1.get_income_per_second()
	var expected_zone_income = base_income * consumer.data_value
	var actual_zone_income = consumer.get_zone_income()

	if abs(actual_zone_income - expected_zone_income) < 0.01:
		print("  PASS: zone income = base(%.1f) * value(%.1f) = %.1f" % [
			base_income, consumer.data_value, actual_zone_income])
	else:
		print("  FAIL: expected %.1f, got %.1f" % [expected_zone_income, actual_zone_income])
		all_passed = false

	consumer.recall(strain1)

	# Test 5: Zone heat accumulates from deployed strains
	print("\n[5] Testing zone heat accumulation...")
	var test_zone = Zone.create(Zone.ZoneType.CORPORATE)
	test_zone.deploy(strain1)

	# Tick for 1 second (delta=1.0)
	var heat_before = test_zone.zone_heat
	test_zone.tick(1.0)
	var heat_after = test_zone.zone_heat

	if heat_after > heat_before:
		print("  PASS: heat increased after tick (%.2f -> %.2f)" % [heat_before, heat_after])
	else:
		print("  FAIL: heat did not increase (before=%.2f, after=%.2f)" % [heat_before, heat_after])
		all_passed = false

	test_zone.recall(strain1)

	# Test 6: Raid check triggers when heat exceeds threshold
	print("\n[6] Testing raid check at high heat...")
	var raid_zone = Zone.create(Zone.ZoneType.GOVERNMENT)
	# Government threshold is 30.0 -- set heat above it
	raid_zone.zone_heat = 35.0  # above threshold
	raid_zone.deploy(strain1)

	# Tick many times to try to trigger a raid (probability-based)
	var raid_happened = false
	var raid_survived = null
	var raid_tick_count: int = 0
	for i in range(100):
		raid_tick_count = i + 1
		var result = raid_zone.tick(1.0)
		if result["raids"].size() > 0:
			raid_happened = true
			raid_survived = result["raids"][0]["survived"]
			break

	if raid_happened:
		print("  PASS: raid triggered after %d ticks (survived=%s)" % [raid_tick_count, raid_survived])
	else:
		print("  FAIL: no raid triggered after 100 ticks at high heat")
		all_passed = false

	# Test 7: Resilience affects survival
	print("\n[7] Testing resilience affects survival...")
	# Create a weak strain (low resilience) and a tough strain (high resilience)
	var weak_strain = Strain.new()
	weak_strain.stealth = 0.1
	weak_strain.speed = 0.1
	weak_strain.payload = 0.1
	weak_strain.resilience = 0.1  # Very low -- should die often
	weak_strain.stability = 0.5
	weak_strain.personality = Strain.Personality.NONE
	weak_strain.generation = 1
	weak_strain.strain_name = "Weakling"

	var tough_strain = Strain.new()
	tough_strain.stealth = 0.1
	tough_strain.speed = 0.1
	tough_strain.payload = 0.1
	tough_strain.resilience = 0.9  # Very high -- should survive often
	tough_strain.stability = 0.5
	tough_strain.personality = Strain.Personality.NONE
	tough_strain.generation = 1
	tough_strain.strain_name = "Tank"

	# Run many raid simulations for each
	var weak_survivals = 0
	var tough_survivals = 0
	var raid_count = 50

	for i in range(raid_count):
		# Simulate a raid on the weak strain
		var test_zone_weak = Zone.create(Zone.ZoneType.GOVERNMENT)
		test_zone_weak.zone_heat = 40.0
		test_zone_weak.deploy(weak_strain)
		# Force a raid by ticking until one happens (max 200 ticks)
		for j in range(200):
			var result = test_zone_weak.tick(1.0)
			if result["raids"].size() > 0:
				if result["raids"][0]["survived"]:
					weak_survivals += 1
				break

		# Simulate a raid on the tough strain
		var test_zone_tough = Zone.create(Zone.ZoneType.GOVERNMENT)
		test_zone_tough.zone_heat = 40.0
		test_zone_tough.deploy(tough_strain)
		for j in range(200):
			var result = test_zone_tough.tick(1.0)
			if result["raids"].size() > 0:
				if result["raids"][0]["survived"]:
					tough_survivals += 1
				break

	print("  Weak strain survived %d/%d raids" % [weak_survivals, raid_count])
	print("  Tough strain survived %d/%d raids" % [tough_survivals, raid_count])

	if tough_survivals > weak_survivals:
		print("  PASS: tough strain survived significantly more raids than weak")
	else:
		print("  FAIL: resilience didn't affect survival (weak=%d, tough=%d)" % [
			weak_survivals, tough_survivals])
		all_passed = false

	# Test 8: Display functions return readable text
	print("\n[8] Testing display functions...")
	var display_zone = Zone.create(Zone.ZoneType.CORPORATE)
	display_zone.deploy(strain1)
	var summary = display_zone.get_summary()
	var status = display_zone.get_short_status()

	if summary.contains("Corporate Server") and summary.contains("Payout"):
		print("  PASS: get_summary() returns readable text")
		print("  ", summary.replace("\n", "\n  "))
	else:
		print("  FAIL: get_summary() malformed: '%s'" % summary)
		all_passed = false

	if status.contains("Corporate") and status.contains("1/2"):
		print("  PASS: get_short_status() returns correct one-liner: '%s'" % status)
	else:
		print("  FAIL: get_short_status() malformed: '%s'" % status)
		all_passed = false

	display_zone.recall(strain1)

	# Test 9: Heat decays when zone is empty
	print("\n[9] Testing heat decay when empty...")
	var decay_zone = Zone.create(Zone.ZoneType.CORPORATE)
	decay_zone.zone_heat = 50.0  # Set some heat
	# Tick without any strains deployed
	decay_zone.tick(5.0)  # 5 seconds

	if decay_zone.zone_heat < 50.0:
		print("  PASS: heat decayed when empty (%.1f -> %.1f)" % [50.0, decay_zone.zone_heat])
	else:
		print("  FAIL: heat did not decay when empty (still %.1f)" % decay_zone.zone_heat)
		all_passed = false

	# Test 10: Dark Web zones have randomized properties
	print("\n[10] Testing Dark Web randomization...")
	var dark_web_1 = Zone.create(Zone.ZoneType.DARK_WEB)
	var dark_web_2 = Zone.create(Zone.ZoneType.DARK_WEB)
	# It's possible (but unlikely) they're identical, so we check that the
	# name is correct and the values are within expected ranges
	if dark_web_1.zone_name == "Dark Web Node":
		if dark_web_1.data_value >= 1.0 and dark_web_1.data_value <= 5.0:
			print("  PASS: Dark Web Node created with data_value=%.2f (range 1.0-5.0)" % dark_web_1.data_value)
		else:
			print("  FAIL: Dark Web data_value out of range: %.2f" % dark_web_1.data_value)
			all_passed = false
	else:
		print("  FAIL: Dark Web zone name wrong: '%s'" % dark_web_1.zone_name)
		all_passed = false

	# Check that two Dark Web zones are likely different (randomized)
	# We'll just verify both are valid. Same values is possible but unlikely.
	print("  Dark Web 1: value=%.2f, det=%.2f, threshold=%.0f" % [
		dark_web_1.data_value, dark_web_1.detection_rate, dark_web_1.detection_threshold])
	print("  Dark Web 2: value=%.2f, det=%.2f, threshold=%.0f" % [
		dark_web_2.data_value, dark_web_2.detection_rate, dark_web_2.detection_threshold])

	# Results
	print("\n=== RESULTS ===")
	if all_passed:
		print("ALL ZONE TESTS PASSED")
	else:
		print("SOME ZONE TESTS FAILED")

	quit()