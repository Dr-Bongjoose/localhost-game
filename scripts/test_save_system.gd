# ============================================================================
# test_save_system.gd - Verification that save_system.gd works correctly
# ============================================================================
# Tests:
# 1. serialize_strain / deserialize_strain round-trip preserves all properties
# 2. serialize_strain_array / deserialize_strain_array round-trip
# 3. serialize_codex / deserialize_codex round-trip preserves entries + metadata
# 4. serialize_zone / deserialize_zone round-trip preserves zone properties
# 5. reconnect_deployed_strains correctly links strains back to zones
# 6. save_game / load_game round-trip through actual file I/O
# 7. has_save() returns false when no save exists, true after saving
# 8. delete_save() removes the save file
# 9. build_save_state produces a Dictionary with all expected keys
# ============================================================================

extends SceneTree

func _init() -> void:
	print("=== LOCALHOST Save System Tests ===")
	var all_passed: bool = true

	# --- Test 1: Strain round-trip ---
	print("\n[1] Testing strain serialization round-trip...")
	var original: Strain = Strain.create_seed()
	original.strain_name = "TestStrain-001"
	original.stealth = 0.75
	original.speed = 0.42
	original.payload = 0.88
	original.resilience = 0.61
	original.stability = 0.33
	original.personality = Strain.Personality.VOLATILE
	original.generation = 5
	original.discovery_date = "2026-06-28"

	var serialized: Dictionary = SaveSystem.serialize_strain(original)
	var restored: Strain = SaveSystem.deserialize_strain(serialized)

	var strain_match: bool = true
	if restored.strain_name != original.strain_name:
		print("  FAIL: name mismatch: %s vs %s" % [restored.strain_name, original.strain_name])
		strain_match = false
	if restored.stealth != original.stealth:
		print("  FAIL: stealth mismatch: %.4f vs %.4f" % [restored.stealth, original.stealth])
		strain_match = false
	if restored.speed != original.speed:
		print("  FAIL: speed mismatch")
		strain_match = false
	if restored.payload != original.payload:
		print("  FAIL: payload mismatch")
		strain_match = false
	if restored.resilience != original.resilience:
		print("  FAIL: resilience mismatch")
		strain_match = false
	if restored.stability != original.stability:
		print("  FAIL: stability mismatch")
		strain_match = false
	if restored.personality != original.personality:
		print("  FAIL: personality mismatch: %d vs %d" % [int(restored.personality), int(original.personality)])
		strain_match = false
	if restored.generation != original.generation:
		print("  FAIL: generation mismatch")
		strain_match = false
	if restored.discovery_date != original.discovery_date:
		print("  FAIL: discovery_date mismatch")
		strain_match = false

	if strain_match:
		print("  PASS: all strain properties preserved through serialize/deserialize")
	else:
		all_passed = false

	# --- Test 2: Strain array round-trip ---
	print("\n[2] Testing strain array serialization...")
	var strain_array: Array[Strain] = []
	strain_array.append(Strain.create_seed())
	strain_array.append(Strain.create_random(2, "Worm"))
	strain_array.append(Strain.create_random(3, "Hybrid"))

	var arr_serialized: Array = SaveSystem.serialize_strain_array(strain_array)
	var arr_restored: Array[Strain] = SaveSystem.deserialize_strain_array(arr_serialized)

	if arr_restored.size() == strain_array.size():
		print("  PASS: array size preserved (%d strains)" % arr_restored.size())
		# Check first strain's name matches
		if arr_restored[0].strain_name == strain_array[0].strain_name:
			print("  PASS: first strain name matches through round-trip")
		else:
			print("  FAIL: first strain name mismatch")
			all_passed = false
	else:
		print("  FAIL: array size mismatch: %d vs %d" % [arr_restored.size(), strain_array.size()])
		all_passed = false

	# --- Test 3: Codex round-trip ---
	print("\n[3] Testing codex serialization...")
	var test_codex: Codex = Codex.new()
	var s1: Strain = Strain.create_seed()
	s1.strain_name = "CodexTest-001"
	var s2: Strain = Strain.create_random(2, "Worm")
	s2.strain_name = "CodexTest-002"
	test_codex.add_strain(s1)
	test_codex.add_strain(s2)
	test_codex.increment_breed_count(s1)
	test_codex.increment_breed_count(s1)
	test_codex.increment_breed_count(s2)

	var codex_serialized: Dictionary = SaveSystem.serialize_codex(test_codex)
	var codex_restored: Codex = SaveSystem.deserialize_codex(codex_serialized)

	if codex_restored.get_count() == test_codex.get_count():
		var codex_ok: bool = true
		# Check breed counts preserved
		for i in range(codex_restored.entries.size()):
			var orig_entry: Dictionary = test_codex.entries[i]
			var rest_entry: Dictionary = codex_restored.entries[i]
			if orig_entry["breed_count"] != rest_entry["breed_count"]:
				print("  FAIL: breed_count mismatch at entry %d" % i)
				codex_ok = false
			if orig_entry["rarity"] != rest_entry["rarity"]:
				print("  FAIL: rarity mismatch at entry %d" % i)
				codex_ok = false
			var orig_strain: Strain = orig_entry["strain"]
			var rest_strain: Strain = rest_entry["strain"]
			if orig_strain.strain_name != rest_strain.strain_name:
				print("  FAIL: strain name mismatch at entry %d" % i)
				codex_ok = false
		if codex_ok:
			print("  PASS: codex entries, breed counts, and rarity preserved")
		else:
			all_passed = false
	else:
		print("  FAIL: codex count mismatch: %d vs %d" % [codex_restored.get_count(), test_codex.get_count()])
		all_passed = false

	# --- Test 4: Zone round-trip ---
	print("\n[4] Testing zone serialization...")
	var test_zone: Zone = Zone.create(Zone.ZoneType.GOVERNMENT)
	test_zone.zone_heat = 25.5
	var zone_strain: Strain = Strain.create_seed()
	zone_strain.strain_name = "ZoneTestStrain"
	test_zone.deployed_strains.append(zone_strain)

	var zone_serialized: Dictionary = SaveSystem.serialize_zone(test_zone)
	var zone_restored: Zone = SaveSystem.deserialize_zone(zone_serialized)

	var zone_ok: bool = true
	if zone_restored.zone_type != test_zone.zone_type:
		print("  FAIL: zone_type mismatch")
		zone_ok = false
	if zone_restored.zone_name != test_zone.zone_name:
		print("  FAIL: zone_name mismatch")
		zone_ok = false
	if abs(zone_restored.data_value - test_zone.data_value) > 0.001:
		print("  FAIL: data_value mismatch: %.4f vs %.4f" % [zone_restored.data_value, test_zone.data_value])
		zone_ok = false
	if abs(zone_restored.zone_heat - test_zone.zone_heat) > 0.001:
		print("  FAIL: zone_heat mismatch: %.4f vs %.4f" % [zone_restored.zone_heat, test_zone.zone_heat])
		zone_ok = false
	# deployed_strain_names should be saved
	var saved_names: Array = zone_serialized["deployed_strain_names"]
	if saved_names.size() == 1 and saved_names[0] == "ZoneTestStrain":
		print("  PASS: deployed strain names saved correctly")
	else:
		print("  FAIL: deployed strain names not saved correctly: %s" % str(saved_names))
		zone_ok = false
	# Restored zone should have empty deployed_strains (reconnected later)
	if zone_restored.deployed_strains.is_empty():
		print("  PASS: restored zone has empty deployed_strains (awaiting reconnect)")
	else:
		print("  FAIL: restored zone should have empty deployed_strains")
		zone_ok = false

	if zone_ok:
		print("  PASS: all zone properties preserved through serialize/deserialize")
	else:
		all_passed = false

	# --- Test 5: Reconnect deployed strains ---
	print("\n[5] Testing deployed strain reconnection...")
	var reconnect_strains: Array[Strain] = []
	var rs1: Strain = Strain.create_seed()
	rs1.strain_name = "ReconnectStrain-001"
	var rs2: Strain = Strain.create_random(2, "Worm")
	rs2.strain_name = "ReconnectStrain-002"
	reconnect_strains.append(rs1)
	reconnect_strains.append(rs2)

	var reconnect_zones: Array[Zone] = []
	reconnect_zones.append(Zone.create(Zone.ZoneType.CONSUMER))
	reconnect_zones.append(Zone.create(Zone.ZoneType.GOVERNMENT))

	# Simulate saved zone data with deployed strain names
	var reconnect_zone_data: Array = [
		{"deployed_strain_names": ["ReconnectStrain-001"]},
		{"deployed_strain_names": ["ReconnectStrain-002"]},
	]

	var deploy_map: Dictionary = SaveSystem.reconnect_deployed_strains(reconnect_zones, reconnect_strains, reconnect_zone_data)

	var reconnect_ok: bool = true
	if reconnect_zones[0].deployed_strains.size() != 1:
		print("  FAIL: zone 0 should have 1 deployed strain, has %d" % reconnect_zones[0].deployed_strains.size())
		reconnect_ok = false
	if reconnect_zones[1].deployed_strains.size() != 1:
		print("  FAIL: zone 1 should have 1 deployed strain, has %d" % reconnect_zones[1].deployed_strains.size())
		reconnect_ok = false
	if reconnect_zones[0].deployed_strains[0].strain_name != "ReconnectStrain-001":
		print("  FAIL: zone 0 has wrong strain")
		reconnect_ok = false
	if deploy_map.has("ReconnectStrain-001") and deploy_map["ReconnectStrain-001"] == reconnect_zones[0]:
		print("  PASS: deploy map correctly maps strain to zone")
	else:
		print("  FAIL: deploy map entry incorrect")
		reconnect_ok = false

	if reconnect_ok:
		print("  PASS: deployed strains reconnected to correct zones")
	else:
		all_passed = false

	# --- Test 6: Full save/load round-trip through file I/O ---
	print("\n[6] Testing full save/load through file I/O...")

	# First, make sure no save exists (clean slate)
	SaveSystem.delete_save()

	if not SaveSystem.has_save():
		print("  PASS: no save file exists (clean slate)")
	else:
		print("  FAIL: save file exists when it shouldn't")
		all_passed = false

	# Build a full save state
	var save_strains: Array[Strain] = []
	save_strains.append(Strain.create_seed())
	save_strains.append(Strain.create_random(2, "Worm"))

	var save_codex: Codex = Codex.new()
	save_codex.add_strain(save_strains[0])
	save_codex.add_strain(save_strains[1])

	var save_zones: Array[Zone] = []
	save_zones.append(Zone.create(Zone.ZoneType.CONSUMER))
	save_zones.append(Zone.create(Zone.ZoneType.CORPORATE))

	# Deploy a strain to a zone
	save_zones[0].deployed_strains.append(save_strains[0])
	var save_deploy_map: Dictionary = {save_strains[0].strain_name: save_zones[0]}

	var full_state: Dictionary = SaveSystem.build_save_state(
		save_strains,  # player_strains
		1234.5,        # player_data
		42.0,          # total_heat
		2.5,           # breed_cooldown
		1,             # active_strain_index
		save_codex,    # codex
		0,             # codex_index
		save_zones,    # zones
		1,             # active_zone_index
		save_deploy_map  # strain_deploy_map
	)

	# Check all expected keys exist
	var expected_keys: Array = ["player_data", "total_heat", "breed_cooldown", "active_strain_index",
		"codex_index", "active_zone_index", "player_strains", "codex", "zones", "deploy_map"]
	var keys_ok: bool = true
	for key in expected_keys:
		if not full_state.has(key):
			print("  FAIL: missing key '%s' in save state" % key)
			keys_ok = false
	if keys_ok:
		print("  PASS: save state has all expected keys")

	# Save to disk
	var save_ok: bool = SaveSystem.save_game(full_state)
	if save_ok:
		print("  PASS: save_game() wrote file successfully")
	else:
		print("  FAIL: save_game() returned false")
		all_passed = false

	# Check file exists
	if SaveSystem.has_save():
		print("  PASS: has_save() returns true after saving")
	else:
		print("  FAIL: has_save() returns false after saving")
		all_passed = false

	# Load it back
	var loaded_state: Dictionary = SaveSystem.load_game()
	if loaded_state.is_empty():
		print("  FAIL: load_game() returned empty dictionary")
		all_passed = false
	else:
		# Verify the simple values survived the round-trip
		var load_ok: bool = true
		if abs(loaded_state.get("player_data", 0.0) - 1234.5) > 0.01:
			print("  FAIL: player_data mismatch: %.2f vs 1234.5" % loaded_state.get("player_data", 0.0))
			load_ok = false
		if abs(loaded_state.get("total_heat", 0.0) - 42.0) > 0.01:
			print("  FAIL: total_heat mismatch")
			load_ok = false
		if abs(loaded_state.get("breed_cooldown", 0.0) - 2.5) > 0.01:
			print("  FAIL: breed_cooldown mismatch")
			load_ok = false
		if loaded_state.get("active_strain_index", -1) != 1:
			print("  FAIL: active_strain_index mismatch: %d vs 1" % loaded_state.get("active_strain_index", -1))
			load_ok = false
		if loaded_state.get("active_zone_index", -1) != 1:
			print("  FAIL: active_zone_index mismatch")
			load_ok = false

		# Verify strains survived
		var loaded_strains: Array = loaded_state.get("player_strains", [])
		if loaded_strains.size() == 2:
			print("  PASS: player_strains array preserved (%d strains)" % loaded_strains.size())
		else:
			print("  FAIL: player_strains size mismatch: %d vs 2" % loaded_strains.size())
			load_ok = false

		# Verify codex survived
		var loaded_codex_data: Dictionary = loaded_state.get("codex", {})
		if loaded_codex_data.get("discovered_count", 0) == 2:
			print("  PASS: codex discovered_count preserved")
		else:
			print("  FAIL: codex discovered_count mismatch")
			load_ok = false

		# Verify zones survived
		var loaded_zones: Array = loaded_state.get("zones", [])
		if loaded_zones.size() == 2:
			# Check zone type preserved
			var z0_type: int = int(loaded_zones[0].get("zone_type", -1))
			if z0_type == int(Zone.ZoneType.CONSUMER):
				print("  PASS: zone types and count preserved")
			else:
				print("  FAIL: zone 0 type mismatch: %d vs %d" % [z0_type, int(Zone.ZoneType.CONSUMER)])
				load_ok = false
		else:
			print("  FAIL: zones size mismatch: %d vs 2" % loaded_zones.size())
			load_ok = false

		# Verify deploy map survived (as strain_name -> zone_index)
		var loaded_deploy_map: Dictionary = loaded_state.get("deploy_map", {})
		if loaded_deploy_map.has(save_strains[0].strain_name):
			if int(loaded_deploy_map[save_strains[0].strain_name]) == 0:
				print("  PASS: deploy map preserved (strain -> zone index 0)")
			else:
				print("  FAIL: deploy map points to wrong zone index")
				load_ok = false
		else:
			print("  FAIL: deploy map missing strain entry")
			load_ok = false

		if load_ok:
			print("  PASS: full save/load round-trip through file I/O successful")
		else:
			all_passed = false

	# --- Test 7: delete_save ---
	print("\n[7] Testing delete_save()...")
	SaveSystem.delete_save()
	if not SaveSystem.has_save():
		print("  PASS: save file deleted, has_save() returns false")
	else:
		print("  FAIL: save file still exists after delete")
		all_passed = false

	# --- Test 8: load_game() with no save returns empty ---
	print("\n[8] Testing load_game() with no save file...")
	var empty_load: Dictionary = SaveSystem.load_game()
	if empty_load.is_empty():
		print("  PASS: load_game() returns empty dict when no save exists")
	else:
		print("  FAIL: load_game() should return empty dict when no save exists")
		all_passed = false

	# --- Results ---
	print("\n=== RESULTS ===")
	if all_passed:
		print("ALL SAVE SYSTEM TESTS PASSED")
	else:
		print("SOME SAVE SYSTEM TESTS FAILED")

	quit()