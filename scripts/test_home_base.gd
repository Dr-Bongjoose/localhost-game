# ============================================================================
# test_home_base.gd - Verification that home_base.gd works correctly
# ============================================================================
# Tests the NEW home base system (passive income + Activate Perimeter):
# 1. assign_defender / recall_defender / is_defender
# 2. Capacity limits (HOME_BASE_CAPACITY)
# 3. is_empty / is_full / get_free_slots
# 4. Passive income calculation (tick_passive)
# 5. Activate Perimeter cooldown calculation (scales with heat)
# 6. Activate Perimeter payout calculation (scales with heat + resilience)
# 7. Activate Perimeter breach chance (scales with heat)
# 8. Breach causes stability damage to defenders
# 9. serialize / deserialize preserves state and reconnects defenders
# ============================================================================

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Home Base Tests (New System) ===")
	var all_passed: bool = true

	# --- Test 1: assign/recall/is_defender ---
	print("\n[1] Testing defender assignment...")
	var base = HomeBase.new()
	var s1 = Strain.create_seed()
	s1.strain_name = "Defender-001"
	s1.resilience = 0.7
	var s2 = Strain.create_seed()
	s2.strain_name = "Defender-002"
	s2.resilience = 0.5

	if base.assign_defender(s1):
		print("  PASS: assigned s1 as defender")
	else:
		print("  FAIL: couldn't assign s1")
		all_passed = false

	if base.is_defender(s1):
		print("  PASS: is_defender(s1) returns true")
	else:
		print("  FAIL: is_defender(s1) should be true")
		all_passed = false

	if not base.is_defender(s2):
		print("  PASS: is_defender(s2) returns false")
	else:
		print("  FAIL: is_defender(s2) should be false")
		all_passed = false

	# Re-assigning same specimen should fail
	if not base.assign_defender(s1):
		print("  PASS: re-assigning s1 fails (already a defender)")
	else:
		print("  FAIL: re-assigning s1 should fail")
		all_passed = false

	# Recall
	if base.recall_defender(s1):
		print("  PASS: recalled s1")
	else:
		print("  FAIL: couldn't recall s1")
		all_passed = false

	if not base.is_defender(s1):
		print("  PASS: is_defender(s1) returns false after recall")
	else:
		print("  FAIL: is_defender(s1) should be false after recall")
		all_passed = false

	# --- Test 2: Capacity limits ---
	print("\n[2] Testing capacity limits...")
	base = HomeBase.new()
	var defenders: Array[Strain] = []
	for i in range(HomeBase.HOME_BASE_CAPACITY):
		var s = Strain.create_seed()
		s.strain_name = "Def-%03d" % i
		defenders.append(s)
		if not base.assign_defender(s):
			print("  FAIL: couldn't assign defender %d" % i)
			all_passed = false

	if base.is_full():
		print("  PASS: base is full at %d defenders" % HomeBase.HOME_BASE_CAPACITY)
	else:
		print("  FAIL: base should be full at %d defenders" % HomeBase.HOME_BASE_CAPACITY)
		all_passed = false

	# Try to assign one more -- should fail
	var extra = Strain.create_seed()
	if not base.assign_defender(extra):
		print("  PASS: rejected assignment when full")
	else:
		print("  FAIL: should reject assignment when full")
		all_passed = false

	if base.get_free_slots() == 0:
		print("  PASS: get_free_slots() returns 0 when full")
	else:
		print("  FAIL: get_free_slots() should be 0 when full")
		all_passed = false

	# --- Test 3: is_empty ---
	print("\n[3] Testing is_empty...")
	base = HomeBase.new()
	if base.is_empty():
		print("  PASS: new base is empty")
	else:
		print("  FAIL: new base should be empty")
		all_passed = false
	base.assign_defender(s1)
	if not base.is_empty():
		print("  PASS: base with defender is not empty")
	else:
		print("  FAIL: base with defender should not be empty")
		all_passed = false

	# --- Test 4: Passive income calculation ---
	print("\n[4] Testing passive income...")
	base = HomeBase.new()
	var d1 = Strain.create_seed()
	d1.strain_name = "Passive-001"
	d1.resilience = 0.6
	var d2 = Strain.create_seed()
	d2.strain_name = "Passive-002"
	d2.resilience = 0.8
	base.assign_defender(d1)
	base.assign_defender(d2)

	# Expected passive income: (0.6 + 0.8) * 0.5 = 0.7 data/sec
	var expected_passive: float = (0.6 + 0.8) * HomeBase.PASSIVE_INCOME_PER_RESILIENCE
	var actual_passive: float = base.get_passive_income_per_second()
	if abs(actual_passive - expected_passive) < 0.01:
		print("  PASS: passive income = %.2f data/sec (expected %.2f)" % [actual_passive, expected_passive])
	else:
		print("  FAIL: passive income %.2f != expected %.2f" % [actual_passive, expected_passive])
		all_passed = false

	# Test tick_passive with enough delta to trigger a tick
	base._passive_timer = 0.0
	var earned: float = base.tick_passive(1.5)  # 1.5 seconds, PASSIVE_TICK_RATE = 1.0
	if abs(earned - expected_passive) < 0.01:
		print("  PASS: tick_passive(1.5) earned %.2f data" % earned)
	else:
		print("  FAIL: tick_passive earned %.2f, expected %.2f" % [earned, expected_passive])
		all_passed = false

	# Test tick with small delta (no tick yet)
	base._passive_timer = 0.0
	earned = base.tick_passive(0.5)  # 0.5 seconds < 1.0 tick rate
	if earned == 0.0:
		print("  PASS: tick_passive(0.5) earned 0 (not enough time)")
	else:
		print("  FAIL: tick_passive(0.5) should earn 0")
		all_passed = false

	# --- Test 5: Perimeter cooldown scales with heat ---
	print("\n[5] Testing perimeter cooldown scaling...")
	base = HomeBase.new()
	var cooldown_0: float = base.calculate_perimeter_cooldown(0.0)
	var cooldown_50: float = base.calculate_perimeter_cooldown(50.0)
	var cooldown_100: float = base.calculate_perimeter_cooldown(100.0)
	print("  Heat 0: %.1fs, Heat 50: %.1fs, Heat 100: %.1fs" % [cooldown_0, cooldown_50, cooldown_100])

	if cooldown_0 == HomeBase.PERIMETER_BASE_COOLDOWN:
		print("  PASS: heat 0 gives base cooldown (%.1fs)" % cooldown_0)
	else:
		print("  FAIL: heat 0 should give base cooldown %.1f" % HomeBase.PERIMETER_BASE_COOLDOWN)
		all_passed = false

	# cooldown_50 = 30 + 50*3 = 180 (capped at max)
	# cooldown_100 = 30 + 100*3 = 330 (capped at max = 180)
	# So cooldown_50 == cooldown_100 == max is correct behavior
	if cooldown_50 > cooldown_0 and cooldown_100 >= cooldown_50:
		print("  PASS: cooldown increases with heat (capped at max)")
	else:
		print("  FAIL: cooldown should increase with heat")
		all_passed = false

	if cooldown_100 <= HomeBase.PERIMETER_MAX_COOLDOWN:
		print("  PASS: cooldown capped at max (%.1fs)" % HomeBase.PERIMETER_MAX_COOLDOWN)
	else:
		print("  FAIL: cooldown should be capped at %.1fs" % HomeBase.PERIMETER_MAX_COOLDOWN)
		all_passed = false

	# --- Test 6: Activate Perimeter payout scales with heat + resilience ---
	print("\n[6] Testing Activate Perimeter payout...")
	base = HomeBase.new()
	var tough_defender = Strain.create_seed()
	tough_defender.strain_name = "ToughDefender"
	tough_defender.resilience = 0.9
	base.assign_defender(tough_defender)

	# Mock global_heat = 0
	var result_0: Dictionary = base.activate_perimeter(0.0)
	var payout_0: float = result_0["payout"]
	var total_resilience: float = 0.9
	var heat_mult_0: float = 1.0 + 0.0 * HomeBase.PERIMETER_HEAT_PAYOUT_SCALE
	var expected_0: float = total_resilience * HomeBase.PERIMETER_BASE_PAYOUT * heat_mult_0

	if result_0["success"] and abs(payout_0 - expected_0) < 0.01:
		print("  PASS: payout at 0 heat = %.1f (expected %.1f)" % [payout_0, expected_0])
	else:
		print("  FAIL: payout %.1f != expected %.1f, success=%s" % [payout_0, expected_0, result_0["success"]])
		all_passed = false

	# Mock global_heat = 50
	# Need to reset cooldown first
	base._perimeter_cooldown = 0.0
	var result_50: Dictionary = base.activate_perimeter(50.0)
	var payout_50: float = result_50["payout"]
	var heat_mult_50: float = 1.0 + 50.0 * HomeBase.PERIMETER_HEAT_PAYOUT_SCALE
	var expected_50: float = total_resilience * HomeBase.PERIMETER_BASE_PAYOUT * heat_mult_50

	if result_50["success"] and abs(payout_50 - expected_50) < 0.01:
		print("  PASS: payout at 50 heat = %.1f (expected %.1f, mult=%.2fx)" % [payout_50, expected_50, heat_mult_50])
	else:
		print("  FAIL: payout %.1f != expected %.1f, success=%s" % [payout_50, expected_50, result_50["success"]])
		all_passed = false

	# Payout should be higher at higher heat
	if payout_50 > payout_0:
		print("  PASS: higher heat gives higher payout")
	else:
		print("  FAIL: higher heat should give higher payout")
		all_passed = false

	# --- Test 7: Breach chance scales with heat ---
	print("\n[7] Testing breach chance scaling...")
	base = HomeBase.new()
	var defender = Strain.create_seed()
	defender.resilience = 0.8
	base.assign_defender(defender)

	# At 0 heat: base chance = 5%
	# At 50 heat: 5% + 50*0.1% = 10%
	# At 100 heat: 5% + 100*0.1% = 15%
	# We can't easily test probability without many trials, but we can verify
	# the formula is used by checking the breach_chance calculation indirectly
	# via the breach_occurred flag over many trials.

	var breach_count_0: int = 0
	var breach_count_100: int = 0
	var trials: int = 200

	# Test at 0 heat
	for i in range(trials):
		base._perimeter_cooldown = 0.0  # Reset cooldown each trial
		var r = base.activate_perimeter(0.0)
		if r["breach_occurred"]:
			breach_count_0 += 1

	# Test at 100 heat
	for i in range(trials):
		base._perimeter_cooldown = 0.0
		var r = base.activate_perimeter(100.0)
		if r["breach_occurred"]:
			breach_count_100 += 1

	var breach_rate_0: float = float(breach_count_0) / trials
	var breach_rate_100: float = float(breach_count_100) / trials
	print("  0 heat: %d/%d breaches (%.1f%%)" % [breach_count_0, trials, breach_rate_0 * 100])
	print("  100 heat: %d/%d breaches (%.1f%%)" % [breach_count_100, trials, breach_rate_100 * 100])

	# Expected: ~5% at 0 heat, ~15% at 100 heat (capped at 50%)
	# Allow generous variance for randomness
	if breach_rate_0 < 0.12 and breach_rate_100 > breach_rate_0:
		print("  PASS: breach chance increases with heat")
	else:
		print("  FAIL: breach chance should increase with heat")
		all_passed = false

	# --- Test 8: Breach causes stability damage to defenders ---
	print("\n[8] Testing breach stability damage...")
	base = HomeBase.new()
	var def1 = Strain.create_seed()
	def1.strain_name = "BreachTest-001"
	def1.stability = 0.8
	var def2 = Strain.create_seed()
	def2.strain_name = "BreachTest-002"
	def2.stability = 0.6
	base.assign_defender(def1)
	base.assign_defender(def2)

	# Force a breach by setting heat very high and running many times
	# (breach chance at 500 heat = 5% + 50% = 55%, capped at 50%)
	var breach_found: bool = false
	var old_stability_1: float = def1.stability
	var old_stability_2: float = def2.stability

	for i in range(100):
		base._perimeter_cooldown = 0.0
		var r = base.activate_perimeter(500.0)  # Very high heat = max breach chance
		if r["breach_occurred"]:
			breach_found = true
			# Check that both defenders took stability damage
			var new_stab_1: float = def1.stability
			var new_stab_2: float = def2.stability
			if new_stab_1 < old_stability_1 and new_stab_2 < old_stability_2:
				print("  PASS: breach caused stability damage to both defenders (%.2f->%.2f, %.2f->%.2f)" % [old_stability_1, new_stab_1, old_stability_2, new_stab_2])
			else:
				print("  FAIL: breach should damage all defenders (stab1: %.2f->%.2f, stab2: %.2f->%.2f)" % [old_stability_1, new_stab_1, old_stability_2, new_stab_2])
				all_passed = false
			# Check breach details structure
			if r["breach_details"].size() == 2:
				print("  PASS: breach_details has entry for each defender")
			else:
				print("  FAIL: breach_details should have 2 entries, has %d" % r["breach_details"].size())
				all_passed = false
			break

	if not breach_found:
		print("  FAIL: no breach occurred in 100 trials at max heat")
		all_passed = false

	# --- Test 9: serialize / deserialize ---
	print("\n[9] Testing serialize/deserialize...")
	base = HomeBase.new()
	var ds1 = Strain.create_seed()
	ds1.strain_name = "SerializeTest-001"
	ds1.resilience = 0.6
	ds1.stability = 0.9
	var ds2 = Strain.create_seed()
	ds2.strain_name = "SerializeTest-002"
	ds2.resilience = 0.8
	ds2.stability = 0.7
	base.assign_defender(ds1)
	base.assign_defender(ds2)
	base._passive_timer = 0.5
	base._perimeter_cooldown = 45.0
	base.passive_data_earned = 123.5
	base.perimeter_activations = 7
	base.perimeter_breaches = 2

	var saved = base.serialize()
	var restored_base = HomeBase.new()
	# Pass the same strain objects for reconnection
	restored_base.deserialize(saved, [ds1, ds2])

	var ser_ok: bool = true
	if restored_base.defenders.size() != 2:
		print("  FAIL: restored base has %d defenders, expected 2" % restored_base.defenders.size())
		ser_ok = false
	if not restored_base.is_defender(ds1):
		print("  FAIL: ds1 not found as defender after restore")
		ser_ok = false
	if not restored_base.is_defender(ds2):
		print("  FAIL: ds2 not found as defender after restore")
		ser_ok = false
	if abs(restored_base._passive_timer - 0.5) > 0.01:
		print("  FAIL: _passive_timer not preserved (%.2f vs 0.5)" % restored_base._passive_timer)
		ser_ok = false
	if abs(restored_base._perimeter_cooldown - 45.0) > 0.01:
		print("  FAIL: _perimeter_cooldown not preserved (%.2f vs 45.0)" % restored_base._perimeter_cooldown)
		ser_ok = false
	if abs(restored_base.passive_data_earned - 123.5) > 0.01:
		print("  FAIL: passive_data_earned not preserved")
		ser_ok = false
	if restored_base.perimeter_activations != 7:
		print("  FAIL: perimeter_activations not preserved")
		ser_ok = false
	if restored_base.perimeter_breaches != 2:
		print("  FAIL: perimeter_breaches not preserved")
		ser_ok = false

	if ser_ok:
		print("  PASS: serialize/deserialize preserves all state and reconnects defenders")

	if not ser_ok:
		all_passed = false

	# --- Test 10: is_perimeter_ready ---
	print("\n[10] Testing is_perimeter_ready...")
	base = HomeBase.new()
	if not base.is_perimeter_ready():
		print("  PASS: empty base -> perimeter not ready")
	else:
		print("  FAIL: empty base should not be ready")
		all_passed = false

	base.assign_defender(ds1)
	base._perimeter_cooldown = 10.0
	if not base.is_perimeter_ready():
		print("  PASS: cooldown active -> perimeter not ready")
	else:
		print("  FAIL: cooldown active should not be ready")
		all_passed = false

	base._perimeter_cooldown = 0.0
	if base.is_perimeter_ready():
		print("  PASS: defenders assigned + no cooldown -> perimeter ready")
	else:
		print("  FAIL: ready base should be ready")
		all_passed = false

	# --- Results ---
	print("\n=== RESULTS ===")
	if all_passed:
		print("ALL HOME BASE TESTS PASSED")
	else:
		print("SOME HOME BASE TESTS FAILED")

	quit()