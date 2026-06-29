# ============================================================================
# save_system.gd - Save and Load System
# ============================================================================
# This script handles converting all game state into a format that can be
# written to a file on disk (serialization) and reading it back (deserialization).
#
# WHY THIS EXISTS:
# Without a save system, every time you close the game you lose everything.
# Your strains, your data, your codex -- all gone. The save system lets the
# game persist between sessions.
#
# HOW IT WORKS:
# 1. SAVE: We take all the live game objects (Strains, Zones, Codex) and
#    convert them into plain Dictionaries (just strings, numbers, arrays).
#    Then we serialize the whole thing to JSON and write it to a file.
# 2. LOAD: We read the JSON file, parse it back into Dictionaries, then
#    reconstruct the live game objects from the saved data.
#
# WHY JSON?
# JSON is human-readable. If something goes wrong, you can open the save file
# in a text editor and see exactly what's in it. It's also Godot's built-in
# serialization format for dictionaries via JSON.stringify() and JSON.parse().
#
# THE TRICKY PART:
# Our game objects (Strain, Zone, Codex) have relationships:
# - A Zone holds references to Strain objects (deployed strains)
# - The Codex holds references to Strain objects (discovered strains)
# - The strain_deploy_map links strain names to Zone objects
# We can't just save object references -- JSON doesn't know what a Strain is.
# So we save everything "by value" (copy the data, not the reference), and
# rebuild the relationships on load by matching strain names.
#
# SAVE FILE LOCATION:
# user://save.json -- "user://" is a Godot virtual path that maps to:
#   Linux:   ~/.local/share/godot/app_userdata/LOCALHOST/save.json
#   Mac:     ~/Library/Application Support/Godot/app_userdata/LOCALHOST/save.json
#   Android: app internal storage (survives app updates)
# ============================================================================

class_name SaveSystem
extends RefCounted

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

## The file path for the save file. "user://" is Godot's cross-platform
## path for per-app persistent storage. It works on every platform without
## hardcoding OS-specific paths.
const SAVE_PATH: String = "user://save.json"

## Current save file version. If we change the save format in the future
## (add new fields, remove old ones), we bump this number. The load function
## can then check the version and handle old saves gracefully instead of
## crashing. For now we only have version 1.
const SAVE_VERSION: int = 1

# ---------------------------------------------------------------------------
# SAVE -- Convert game state to JSON file
# ---------------------------------------------------------------------------

## Saves the entire game state to disk.
## Returns true if successful, false if the file couldn't be written.
##
## The state_dict parameter is a Dictionary containing all the game state
## from main.gd. We assemble it in main.gd and pass it here. This keeps
## SaveSystem generic -- it doesn't need to know about main.gd's internals.
static func save_game(state_dict: Dictionary) -> bool:
	# --- BUILD THE SAVE STRUCTURE ---
	# We wrap everything in a top-level dictionary with a version number.
	# This way, if we change the format later, load_game() can detect old
	# versions and migrate them instead of crashing.
	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"game_state": state_dict,
	}

	# --- SERIALIZE TO JSON ---
	# JSON.stringify() converts a Dictionary to a JSON string.
	# The second argument ("\t") is for indentation -- makes the file
	# human-readable when you open it in a text editor. Not required but
	# very helpful for debugging.
	var json_string: String = JSON.stringify(save_data, "\t")

	# --- WRITE TO FILE ---
	# FileAccess is Godot's file I/O class. We open the file for writing
	# (FileAccess.WRITE creates or overwrites the file).
	# If the directory doesn't exist, Godot creates it automatically
	# for user:// paths.
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		# If the file couldn't be opened, print the error for debugging
		push_error("SaveSystem: Failed to open save file for writing: " + str(FileAccess.get_open_error()))
		return false

	# Write the JSON string to the file and close it
	file.store_string(json_string)
	file.close()

	print("SaveSystem: Game saved to %s" % SAVE_PATH)
	return true

# ---------------------------------------------------------------------------
# LOAD -- Read JSON file and convert back to game state
# ---------------------------------------------------------------------------

## Loads the game state from disk.
## Returns a Dictionary with the game state, or null if no save exists
## or the file is corrupted.
##
## The caller (main.gd) checks for null and starts a new game if needed.
static func load_game() -> Dictionary:
	# --- CHECK IF SAVE FILE EXISTS ---
	if not FileAccess.file_exists(SAVE_PATH):
		print("SaveSystem: No save file found at %s" % SAVE_PATH)
		return {}

	# --- READ THE FILE ---
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveSystem: Failed to open save file for reading: " + str(FileAccess.get_open_error()))
		return {}

	var json_string: String = file.get_as_text()
	file.close()

	# --- PARSE JSON ---
	# JSON.parse() converts a JSON string back to a Dictionary (or Array).
	# It returns a JSON object with a .result property and an .error property.
	# We check .error to make sure the file isn't corrupted.
	var json: JSON = JSON.new()
	var error: int = json.parse(json_string)
	if error != OK:
		push_error("SaveSystem: JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}

	var save_data: Dictionary = json.data

	# --- VERSION CHECK ---
	# If the save file has a different version than what we expect,
	# we could migrate it here. For now we just warn.
	var version: int = save_data.get("version", 0)
	if version != SAVE_VERSION:
		push_warning("SaveSystem: Save file version %d doesn't match current version %d" % [version, SAVE_VERSION])
		# In the future, we'd add migration logic here.
		# For now, we try to load it anyway.

	print("SaveSystem: Game loaded from %s" % SAVE_PATH)
	return save_data.get("game_state", {})

# ---------------------------------------------------------------------------
# STRAIN SERIALIZATION
# ---------------------------------------------------------------------------
# These functions convert Strain objects to/from plain Dictionaries.
# This is the core of the save system -- almost everything else builds on this.

## Converts a Strain object into a plain Dictionary that can be saved as JSON.
## We pull out every property individually because JSON can't store Godot
## objects -- only primitives (String, int, float, bool) and nested structures
## (Dictionary, Array).
##
## Note on personality: enums in GDScript are integers under the hood.
#  Personality.NONE = 0, AGGRESSIVE = 1, etc. We save the int and cast it
## back to the enum on load.
static func serialize_strain(strain: Strain) -> Dictionary:
	return {
		"strain_name": strain.strain_name,
		"generation": strain.generation,
		"discovery_date": strain.discovery_date,
		"stealth": strain.stealth,
		"speed": strain.speed,
		"payload": strain.payload,
		"resilience": strain.resilience,
		"stability": strain.stability,
		# Personality is an enum, which is just an int. We save it as an int
		# and convert it back to Strain.Personality on load.
		"personality": int(strain.personality),
	}

## Converts a saved Dictionary back into a live Strain object.
## This is the reverse of serialize_strain -- we create a new Strain
## and push all the saved values into it.
static func deserialize_strain(data: Dictionary) -> Strain:
	var strain: Strain = Strain.new()
	strain.strain_name = data.get("strain_name", "Unknown")
	strain.generation = data.get("generation", 1)
	strain.discovery_date = data.get("discovery_date", "")
	strain.stealth = data.get("stealth", 0.3)
	strain.speed = data.get("speed", 0.5)
	strain.payload = data.get("payload", 0.5)
	strain.resilience = data.get("resilience", 0.4)
	strain.stability = data.get("stability", 0.7)
	# Convert the saved int back to the Personality enum.
	# In GDScript, you cast an int to an enum like this: int_value as EnumType
	strain.personality = data.get("personality", 0) as Strain.Personality
	return strain

## Serializes an array of Strains into an array of Dictionaries.
## Used for the player's strain collection.
static func serialize_strain_array(strains: Array[Strain]) -> Array:
	var result: Array = []
	for strain in strains:
		result.append(serialize_strain(strain))
	return result

## Deserializes an array of Dictionaries back into an array of Strains.
static func deserialize_strain_array(data: Array) -> Array[Strain]:
	var result: Array[Strain] = []
	for entry in data:
		result.append(deserialize_strain(entry))
	return result

# ---------------------------------------------------------------------------
# CODEX SERIALIZATION
# ---------------------------------------------------------------------------
# The Codex is trickier because it stores Strain objects inside Dictionaries
# along with metadata (breed_count, rarity, first_seen). We need to serialize
# both the strain AND the metadata, then rebuild everything on load.

## Serializes the entire codex (all entries) into a saveable Dictionary.
static func serialize_codex(codex: Codex) -> Dictionary:
	var entries_data: Array = []
	for entry in codex.entries:
		# Each entry is a Dictionary with: strain, breed_count, rarity, first_seen
		# We serialize the strain (convert to plain dict) and keep the rest as-is.
		entries_data.append({
			"strain": serialize_strain(entry["strain"]),
			"breed_count": entry["breed_count"],
			"rarity": int(entry["rarity"]),
			"first_seen": entry["first_seen"],
		})

	return {
		"discovered_count": codex.discovered_count,
		"entries": entries_data,
	}

## Deserializes a saved codex Dictionary back into a live Codex object.
static func deserialize_codex(data: Dictionary) -> Codex:
	var codex: Codex = Codex.new()
	codex.discovered_count = data.get("discovered_count", 0)

	var entries_data: Array = data.get("entries", [])
	for entry_data in entries_data:
		# Rebuild each entry: deserialize the strain, convert rarity int back to enum
		var strain: Strain = deserialize_strain(entry_data["strain"])
		var rarity: Codex.Rarity = entry_data["rarity"] as Codex.Rarity
		var entry: Dictionary = {
			"strain": strain,
			"breed_count": entry_data["breed_count"],
			"rarity": rarity,
			"first_seen": entry_data["first_seen"],
		}
		codex.entries.append(entry)

	return codex

# ---------------------------------------------------------------------------
# ZONE SERIALIZATION
# ---------------------------------------------------------------------------
# Zones are the trickiest because they hold live Strain references
# (deployed_strains). We can't save object references in JSON, so we save
# the names of deployed strains instead. On load, we reconnect them by
# matching names with the player's strain collection.
#
# We also save the zone's current state (heat, properties) so the game
# resumes exactly where you left off.

## Serializes a zone, including the NAMES of deployed strains (not the objects).
## We save names because:
## 1. The strain objects are saved separately in the player's strain array
## 2. On load, we reconnect by finding the strain with that name
## 3. This avoids duplicating strain data (one copy in player_strains, one in zones)
##
## Parameters:
##   zone: the Zone to serialize
##   strain_deploy_map: needed to preserve deployment order (which strains are here)
static func serialize_zone(zone: Zone) -> Dictionary:
	# Save the names of deployed strains so we can reconnect them on load
	var deployed_names: Array = []
	for strain in zone.deployed_strains:
		deployed_names.append(strain.strain_name)

	return {
		"zone_type": int(zone.zone_type),
		"zone_name": zone.zone_name,
		"data_value": zone.data_value,
		"detection_rate": zone.detection_rate,
		"detection_threshold": zone.detection_threshold,
		"capacity": zone.capacity,
		"zone_heat": zone.zone_heat,
		"locked": zone.locked,
		"deployed_strain_names": deployed_names,
	}

## Deserializes a saved zone Dictionary back into a live Zone object.
## Note: This does NOT reconnect deployed strains -- that's done in
## deserialize_game_state() after we have the player's strain collection.
## We just set up the zone's properties and leave deployed_strains empty.
static func deserialize_zone(data: Dictionary) -> Zone:
	var zone: Zone = Zone.new()
	zone.zone_type = data.get("zone_type", 0) as Zone.ZoneType
	zone.zone_name = data.get("zone_name", "Unknown Zone")
	zone.data_value = data.get("data_value", 1.0)
	zone.detection_rate = data.get("detection_rate", 1.0)
	zone.detection_threshold = data.get("detection_threshold", 50.0)
	zone.capacity = data.get("capacity", 2)
	zone.zone_heat = data.get("zone_heat", 0.0)
	zone.locked = data.get("locked", false)
	# deployed_strains starts empty -- reconnected later by deploy_strains_by_name()
	return zone

## After loading zones and player_strains, reconnect deployed strains
## by matching names. This is called from main.gd after load_game().
##
## We do it this way because:
## - The strain OBJECTS live in player_strains (loaded first)
## - The zones only saved the NAMES of deployed strains
## - We need to find the actual Strain objects by name and put them
##   back into the zone's deployed_strains array
##
## Returns a Dictionary mapping strain_name -> Zone, to rebuild
## main.gd's strain_deploy_map.
static func reconnect_deployed_strains(zones: Array[Zone], player_strains: Array[Strain], zone_data: Array) -> Dictionary:
	# Build a lookup: strain_name -> Strain object, for fast searching
	var strain_by_name: Dictionary = {}
	for strain in player_strains:
		strain_by_name[strain.strain_name] = strain

	# For each zone, find the strains by name and deploy them
	var deploy_map: Dictionary = {}
	for i in range(zones.size()):
		var zone: Zone = zones[i]
		var saved_names: Array = zone_data[i].get("deployed_strain_names", [])

		for name in saved_names:
			if strain_by_name.has(name):
				var strain: Strain = strain_by_name[name]
				zone.deployed_strains.append(strain)
				# Record in the deploy map: this strain is in this zone
				deploy_map[name] = zone
			else:
				# Strain was destroyed but still listed in zone save?
				# This shouldn't happen, but we handle it gracefully.
				push_warning("SaveSystem: Deployed strain '%s' not found in player collection" % name)

	return deploy_map

# ---------------------------------------------------------------------------
# FULL GAME STATE SERIALIZATION
# ---------------------------------------------------------------------------
# These are convenience functions that main.gd calls to build the complete
# save dictionary and to restore the complete game state from a save.

## Builds the complete save dictionary from main.gd's game state.
## Call this right before SaveSystem.save_game().
##
## Parameters are all the state from main.gd that needs to persist.
static func build_save_state(
		player_strains: Array[Strain],
		player_data: float,
		total_heat: float,
		breed_cooldown: float,
		active_strain_index: int,
		codex: Codex,
		codex_index: int,
		zones: Array[Zone],
		active_zone_index: int,
		strain_deploy_map: Dictionary,
		home_base: HomeBase
	) -> Dictionary:

	return {
		# --- SIMPLE VALUES ---
		"player_data": player_data,
		"total_heat": total_heat,
		"breed_cooldown": breed_cooldown,
		"active_strain_index": active_strain_index,
		"codex_index": codex_index,
		"active_zone_index": active_zone_index,

		# --- STRAINS ---
		"player_strains": serialize_strain_array(player_strains),

		# --- CODEX ---
		"codex": serialize_codex(codex),

		# --- ZONES ---
		"zones": _serialize_zone_array(zones),

		# --- DEPLOY MAP ---
		"deploy_map": _serialize_deploy_map(strain_deploy_map, zones),

		# --- HOME BASE ---
		"home_base": home_base.serialize(),
	}

## Helper: serializes an array of Zones
static func _serialize_zone_array(zones: Array[Zone]) -> Array:
	var result: Array = []
	for zone in zones:
		result.append(serialize_zone(zone))
	return result

## Helper: converts strain_deploy_map (strain_name -> Zone) to a saveable
## format (strain_name -> zone_index int). We need the zones array to look
## up which index each Zone is.
static func _serialize_deploy_map(deploy_map: Dictionary, zones: Array[Zone]) -> Dictionary:
	var result: Dictionary = {}
	for strain_name in deploy_map:
		var zone: Zone = deploy_map[strain_name]
		var idx: int = zones.find(zone)
		# If the zone is found, save the index. If not (shouldn't happen), skip it.
		if idx != -1:
			result[strain_name] = idx
	return result

# ---------------------------------------------------------------------------
# SAVE FILE MANAGEMENT
# ---------------------------------------------------------------------------

## Checks if a save file exists. Used by main.gd to decide whether to
## load a save or start a new game.
static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Deletes the save file. Used when starting a new game or if the save
## is corrupted and needs to be wiped.
static func delete_save() -> bool:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("SaveSystem: Failed to open user:// directory")
		return false
	if dir.file_exists("save.json"):
		var error: int = dir.remove("save.json")
		if error != OK:
			push_error("SaveSystem: Failed to delete save file: " + str(error))
			return false
		print("SaveSystem: Save file deleted")
	return true