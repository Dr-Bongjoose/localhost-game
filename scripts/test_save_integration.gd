# ============================================================================
# test_save_integration.gd - Integration test: game runs, saves, reloads
# ============================================================================
# This test simulates a real game session:
# 1. Delete any existing save
# 2. Build a fake game state (strains, codex, zones with deployments)
# 3. Save it
# 4. Load it back
# 5. Verify ALL state matches the original -- strains, codex, zones, deploy map
# 6. Simulate a raid destroying a strain, save again, reload, verify
# ============================================================================

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Save Integration Tests ===")
	var all_passed: bool = true

	# Clean slate
	SaveSystem.delete_save()

	# --- Build a realistic game state ---
	print("\n[1] Building realistic game state...")
	var strains: Array[Strain] = []
	var s1: Strain = Strain.create_seed()
	s1.strain_name = "Alpha-001"
	s1.stealth = 0.6
	s1.speed = 0.7
	s1.payload = 0.8
	s1.resilience = 0.5
	s1.stability = 0.9
	s1.personality = Strain.Personality.AGGRESSIVE
	s1.generation = 1
	strains.append(s1)

	var s2: Strain = Strain.create_random(2, "Worm")
	s2.strain_name = "Beta-002"
	strains.append(s2)

	# Breed a child
	var s3: Strain = Breeding.breed(s1, s2)
	s3.strain_name = "Gamma-003"
	strains.append(s3)

	var game_codex: Codex = Codex.new()
	for s in strains:
		game_codex.add_strain(s)
	game_codex.increment_breed_count(s1)
	game_codex.increment_breed_count(s2)

	var game_zones: Array[Zone] = []
	game_zones.append(Zone.create(Zone.ZoneType.CONSUMER))
	game_zones.append(Zone.create(Zone.ZoneType.GOVERNMENT))

	# Deploy s1 to consumer zone, s3 to government zone
	game_zones[0].deployed_strains.append(s1)
	game_zones[1].deployed_strains.append(s3)
	var game_deploy_map: Dictionary = {
		s1.strain_name: game_zones[0],
		s3.strain_name: game_zones[1],
	}

	print("  Built: %d strains, %d codex entries, %d zones with deployments" % [
		strains.size(), game_codex.get_count(), game_zones.size()
	])

	# --- Save the state ---
	print("\n[2] Saving game state...")
	var state: Dictionary = SaveSystem.build_save_state(
		strains, 5000.0, 15.0, 0.0, 2,
		game_codex, 0, game_zones, 1, game_deploy_map,
		HomeBase.new()
	)
	var saved: bool = SaveSystem.save_game(state)
	if not saved:
		print("  FAIL: save failed")
		all_passed = false
	else:
		print("  PASS: state saved")

	# --- Load it back ---
	print("\n[3] Loading game state...")
	var loaded: Dictionary = SaveSystem.load_game()
	if loaded.is_empty():
		print("  FAIL: load returned empty")
		quit()
		return

	# --- Verify simple values ---
	print("\n[4] Verifying simple values...")
	var simple_ok: bool = true
	if abs(loaded.get("player_data", 0.0) - 5000.0) > 0.1:
		print("  FAIL: player_data: %.2f vs 5000.0" % loaded.get("player_data", 0.0))
		simple_ok = false
	if abs(loaded.get("total_heat", 0.0) - 15.0) > 0.1:
		print("  FAIL: total_heat mismatch")
		simple_ok = false
	if loaded.get("active_strain_index", -1) != 2:
		print("  FAIL: active_strain_index: %d vs 2" % loaded.get("active_strain_index", -1))
		simple_ok = false
	if loaded.get("active_zone_index", -1) != 1:
		print("  FAIL: active_zone_index: %d vs 1" % loaded.get("active_zone_index", -1))
		simple_ok = false
	if simple_ok:
		print("  PASS: all simple values match")

	# --- Restore strains and verify ---
	print("\n[5] Verifying strain restoration...")
	var restored_strains: Array[Strain] = SaveSystem.deserialize_strain_array(loaded.get("player_strains", []))
	var strain_ok: bool = true
	if restored_strains.size() != strains.size():
		print("  FAIL: strain count: %d vs %d" % [restored_strains.size(), strains.size()])
		strain_ok = false
	else:
		# Check Alpha-001's properties specifically
		var alpha: Strain = restored_strains[0]
		if alpha.strain_name != "Alpha-001":
			print("  FAIL: strain 0 name: %s vs Alpha-001" % alpha.strain_name)
			strain_ok = false
		if abs(alpha.stealth - 0.6) > 0.001:
			print("  FAIL: Alpha stealth: %.4f vs 0.6" % alpha.stealth)
			strain_ok = false
		if alpha.personality != Strain.Personality.AGGRESSIVE:
			print("  FAIL: Alpha personality: %d vs %d" % [int(alpha.personality), int(Strain.Personality.AGGRESSIVE)])
			strain_ok = false
		# Check Gamma-003 (the bred child) exists
		var gamma: Strain = restored_strains[2]
		if gamma.strain_name != "Gamma-003":
			print("  FAIL: strain 2 name: %s vs Gamma-003" % gamma.strain_name)
			strain_ok = false
		if gamma.generation != 3:  # max(1,2)+1 = 3
			print("  FAIL: Gamma generation: %d vs 3" % gamma.generation)
			strain_ok = false
	if strain_ok:
		print("  PASS: all strains restored with correct properties")

	# --- Restore codex and verify ---
	print("\n[6] Verifying codex restoration...")
	var restored_codex: Codex = SaveSystem.deserialize_codex(loaded.get("codex", {}))
	var codex_ok: bool = true
	if restored_codex.get_count() != 3:
		print("  FAIL: codex count: %d vs 3" % restored_codex.get_count())
		codex_ok = false
	else:
		# Check breed counts
		var found_breed_counts: bool = false
		for entry in restored_codex.entries:
			var es: Strain = entry["strain"]
			if es.strain_name == "Alpha-001":
				if entry["breed_count"] == 1:
					found_breed_counts = true
				else:
					print("  FAIL: Alpha breed_count: %d vs 1" % entry["breed_count"])
					codex_ok = false
	if codex_ok:
		print("  PASS: codex restored with all entries and breed counts")

	# --- Restore zones and reconnect deployments ---
	print("\n[7] Verifying zone restoration and deployment reconnection...")
	var zone_data: Array = loaded.get("zones", [])
	var restored_zones: Array[Zone] = []
	for zd in zone_data:
		restored_zones.append(SaveSystem.deserialize_zone(zd))

	var restored_deploy_map: Dictionary = SaveSystem.reconnect_deployed_strains(restored_zones, restored_strains, zone_data)

	var zone_ok: bool = true
	if restored_zones.size() != 2:
		print("  FAIL: zone count: %d vs 2" % restored_zones.size())
		zone_ok = false
	else:
		# Consumer zone should have Alpha-001 deployed
		if restored_zones[0].deployed_strains.size() != 1:
			print("  FAIL: consumer zone deployed count: %d vs 1" % restored_zones[0].deployed_strains.size())
			zone_ok = false
		elif restored_zones[0].deployed_strains[0].strain_name != "Alpha-001":
			print("  FAIL: consumer zone has wrong strain: %s" % restored_zones[0].deployed_strains[0].strain_name)
			zone_ok = false
		# Government zone should have Gamma-003 deployed
		if restored_zones[1].deployed_strains.size() != 1:
			print("  FAIL: government zone deployed count: %d vs 1" % restored_zones[1].deployed_strains.size())
			zone_ok = false
		elif restored_zones[1].deployed_strains[0].strain_name != "Gamma-003":
			print("  FAIL: government zone has wrong strain: %s" % restored_zones[1].deployed_strains[0].strain_name)
			zone_ok = false
		# Check deploy map
		if not restored_deploy_map.has("Alpha-001"):
			print("  FAIL: deploy map missing Alpha-001")
			zone_ok = false
		elif restored_deploy_map["Alpha-001"] != restored_zones[0]:
			print("  FAIL: deploy map points Alpha-001 to wrong zone")
			zone_ok = false
	if zone_ok:
		print("  PASS: zones restored, deployments reconnected correctly")

	# --- Simulate a raid destroying a strain ---
	print("\n[8] Simulating strain destruction + re-save...")
	# Gamma-003 gets destroyed in a raid
	var gamma_idx: int = -1
	for i in range(restored_strains.size()):
		if restored_strains[i].strain_name == "Gamma-003":
			gamma_idx = i
			break

	if gamma_idx >= 0:
		# Remove from zone
		restored_zones[1].deployed_strains.erase(restored_strains[gamma_idx])
		restored_deploy_map.erase("Gamma-003")
		# Remove from player collection
		restored_strains.remove_at(gamma_idx)

	# Re-save the updated state
	var state_after_raid: Dictionary = SaveSystem.build_save_state(
		restored_strains, 5200.0, 20.0, 0.0, 0,
		restored_codex, 0, restored_zones, 0, restored_deploy_map,
		HomeBase.new()
	)
	SaveSystem.save_game(state_after_raid)

	# Load again and verify Gamma-003 is gone from strains but still in codex
	var reload: Dictionary = SaveSystem.load_game()
	var reload_strains: Array[Strain] = SaveSystem.deserialize_strain_array(reload.get("player_strains", []))
	var reload_codex: Codex = SaveSystem.deserialize_codex(reload.get("codex", {}))

	var raid_ok: bool = true
	if reload_strains.size() != 2:
		print("  FAIL: after raid, strain count: %d vs 2" % reload_strains.size())
		raid_ok = false
	else:
		# Gamma-003 should not be in player strains
		var gamma_still_there: bool = false
		for s in reload_strains:
			if s.strain_name == "Gamma-003":
				gamma_still_there = true
		if gamma_still_there:
			print("  FAIL: Gamma-003 should have been removed from player strains")
			raid_ok = false
	# But Gamma-003 should still be in the codex
	var gamma_in_codex: bool = false
	for entry in reload_codex.entries:
		var es: Strain = entry["strain"]
		if es.strain_name == "Gamma-003":
			gamma_in_codex = true
	if not gamma_in_codex:
		print("  FAIL: Gamma-003 should still be in codex after destruction")
		raid_ok = false

	if raid_ok:
		print("  PASS: destroyed strain removed from collection but preserved in codex")

	# --- Cleanup ---
	SaveSystem.delete_save()

	# --- Results ---
	print("\n=== RESULTS ===")
	if all_passed and simple_ok and strain_ok and codex_ok and zone_ok and raid_ok:
		print("ALL SAVE INTEGRATION TESTS PASSED")
	else:
		print("SOME SAVE INTEGRATION TESTS FAILED")
		all_passed = false

	quit()