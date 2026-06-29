# ============================================================================
# test_home_base.gd - Verification that home_base.gd works correctly
# ============================================================================
# Tests:
# 1. assign_defender / recall_defender / is_defender
# 2. Capacity limits (HOME_BASE_CAPACITY)
# 3. is_empty / is_full / get_free_slots
# 4. calculate_attack_interval scales with heat
# 5. tick() triggers attack at the right interval
# 6. resolve_attack with defenders -- survival rolls and data rewards
# 7. resolve_attack with no defenders -- breach
# 8. Data reward formula: attack_strength * resilience * REWARD_MULTIPLIER
# 9. serialize / deserialize preserves state and reconnects defenders
# ============================================================================

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Home Base Tests ===")
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

	# --- Test 4: Attack interval scales with heat ---
	print("\n[4] Testing attack interval scaling...")
	base = HomeBase.new()
	var interval_0 = base.calculate_attack_interval(0.0)
	var interval_50 = base.calculate_attack_interval(50.0)
	var interval_100 = base.calculate_attack_interval(100.0)
	print("  Heat 0: %.1fs, Heat 50: %.1fs, Heat 100: %.1fs" % [interval_0, interval_50, interval_100])

	if interval_0 > interval_50 and interval_50 > interval_100:
		print("  PASS: interval decreases as heat increases")
	else:
		print("  FAIL: interval should decrease with heat")
		all_passed = false

	if interval_0 == HomeBase.ATTACK_INTERVAL_BASE:
		print("  PASS: heat 0 gives base interval (%.1fs)" % interval_0)
	else:
		print("  FAIL: heat 0 should give base interval")
		all_passed = false

	if interval_100 == HomeBase.ATTACK_INTERVAL_MIN:
		print("  PASS: heat 100 gives min interval (%.1fs)" % interval_100)
	else:
		print("  FAIL: heat 100 should give min interval")
		all_passed = false

	# --- Test 5: tick triggers attack ---
	print("\n[5] Testing tick triggers attack...")
	base = HomeBase.new()
	# tick() recalculates attack_interval from heat, so we use high heat
	# to get a short interval (heat 200 -> min interval 15s, but we use big delta)
	base.attack_timer = 0.0
	var triggered: bool = base.tick(5.0, 0.0)  # 5s tick, interval is 60s at heat 0
	if not triggered:
		print("  PASS: no attack at 5s into 60s interval")
	else:
		print("  FAIL: shouldn't trigger at 5s into 60s interval")
		all_passed = false
	# Now tick enough to pass the interval
	triggered = base.tick(56.0, 0.0)  # 5+56=61s, past 60s interval
	if triggered:
		print("  PASS: attack triggered after interval passed")
	else:
		print("  FAIL: should trigger after interval")
		all_passed = false

	# --- Test 6: resolve_attack with defenders ---
	print("\n[6] Testing attack resolution with defenders...")
	base = HomeBase.new()
	var tough = Strain.create_seed()
	tough.strain_name = "Tough"
	tough.resilience = 0.9
	base.assign_defender(tough)

	# Run 20 attacks with 0 heat (weak attacks 0.1-0.5)
	var survived_count: int = 0
	var total_data: float = 0.0
	var breach_count: int = 0
	for i in range(20):
		var result = base.resolve_attack(0.0)
		if not result["breach"]:
			survived_count += 1
			total_data += result["total_reward"]
		else:
			breach_count += 1

	print("  20 attacks at 0 heat with resilience 0.9 defender:")
	print("  Survived: %d, Breaches: %d, Data earned: %.1f" % [survived_count, breach_count, total_data])
	if survived_count > breach_count:
		print("  PASS: tough defender mostly survives at 0 heat")
	else:
		print("  FAIL: tough defender should mostly survive at 0 heat")
		all_passed = false

	# --- Test 7: resolve_attack with no defenders = breach ---
	print("\n[7] Testing breach with no defenders...")
	base = HomeBase.new()
	var breach_result = base.resolve_attack(0.0)
	if breach_result["breach"]:
		print("  PASS: no defenders = breach")
	else:
		print("  FAIL: no defenders should cause breach")
		all_passed = false
	if breach_result["total_reward"] == 0.0:
		print("  PASS: breach earns 0 data")
	else:
		print("  FAIL: breach should earn 0 data")
		all_passed = false
	if base.breaches_suffered == 1:
		print("  PASS: breaches_suffered incremented")
	else:
		print("  FAIL: breaches_suffered should be 1")
		all_passed = false

	# --- Test 8: Data reward formula ---
	print("\n[8] Testing data reward formula...")
	# Formula: attack_strength * resilience * REWARD_MULTIPLIER
	# With 0 heat: attack_strength is 0.1 to 0.5
	# With resilience 0.9: reward = strength * 0.9 * 50
	# For strength 0.3: reward = 0.3 * 0.9 * 50 = 13.5
	# We can't control the random strength, but we can verify the formula
	# by checking the result structure has the right fields
	base = HomeBase.new()
	var s = Strain.create_seed()
	s.resilience = 0.8
	base.assign_defender(s)
	var res = base.resolve_attack(0.0)
	if res.has("defender_results") and res["defender_results"].size() > 0:
		var dr = res["defender_results"][0]
		if dr.has("reward") and dr.has("survived") and dr.has("roll"):
			print("  PASS: defender result has reward, survived, roll fields")
		else:
			print("  FAIL: defender result missing fields")
			all_passed = false
		# Verify reward formula if survived
		if dr["survived"]:
			var expected = res["attack_strength"] * s.resilience * HomeBase.REWARD_MULTIPLIER
			if abs(dr["reward"] - expected) < 0.01:
				print("  PASS: reward = attack_strength * resilience * multiplier (%.2f)" % dr["reward"])
			else:
				print("  FAIL: reward %.2f != expected %.2f" % [dr["reward"], expected])
				all_passed = false
		else:
			if dr["reward"] == 0.0:
				print("  PASS: failed defender earns 0 reward")
			else:
				print("  FAIL: failed defender should earn 0")
				all_passed = false
	else:
		print("  FAIL: no defender results in attack resolution")
		all_passed = false

	# --- Test 9: serialize / deserialize ---
	print("\n[9] Testing serialize/deserialize...")
	base = HomeBase.new()
	var ds1 = Strain.create_seed()
	ds1.strain_name = "SerializeTest-001"
	ds1.resilience = 0.6
	var ds2 = Strain.create_seed()
	ds2.strain_name = "SerializeTest-002"
	ds2.resilience = 0.8
	base.assign_defender(ds1)
	base.assign_defender(ds2)
	base.attacks_resisted = 5
	base.breaches_suffered = 2
	base.defense_data_earned = 42.5
	base.attack_timer = 15.0

	var saved = base.serialize()
	var restored_base = HomeBase.new()
	# Pass both specimens in the player's collection for reconnection
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
	if restored_base.attacks_resisted != 5:
		print("  FAIL: attacks_resisted not preserved (%d vs 5)" % restored_base.attacks_resisted)
		ser_ok = false
	if restored_base.breaches_suffered != 2:
		print("  FAIL: breaches_suffered not preserved")
		ser_ok = false
	if abs(restored_base.defense_data_earned - 42.5) > 0.01:
		print("  FAIL: defense_data_earned not preserved")
		ser_ok = false
	if abs(restored_base.attack_timer - 15.0) > 0.01:
		print("  FAIL: attack_timer not preserved")
		ser_ok = false
	if ser_ok:
		print("  PASS: serialize/deserialize preserves all state and reconnects defenders")

	if not ser_ok:
		all_passed = false

	# --- Results ---
	print("\n=== RESULTS ===")
	if all_passed:
		print("ALL HOME BASE TESTS PASSED")
	else:
		print("SOME HOME BASE TESTS FAILED")

	quit()