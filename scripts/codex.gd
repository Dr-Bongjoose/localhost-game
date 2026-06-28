# ============================================================================
# codex.gd - The Strain Codex (Bestiary)
# ============================================================================
# The Codex is a permanent record of every strain the player has ever
# discovered. Even if a strain is lost (deployed and destroyed in a zone),
# its codex entry persists. Think of it like a Pokedex for malware.
#
# The Codex tracks:
# - Every strain ever created (discovered_strains)
# - How many times each strain has been used in breeding (breed_count)
# - A rarity tier for each strain based on trait quality
#
# Rarity tiers (from the design doc):
#   Common    -- easily bred, mediocre traits
#   Uncommon  -- decent trait combinations
#   Rare      -- good traits or minor mutations
#   Legendary -- exceptional traits or major mutations
#   Mythic    -- reserved for special events (not achievable in Phase 1)
#
# The codex is an autoload singleton (we'll register it in project.godot)
# so it persists across scene changes. For now, main.gd will hold a
# reference to it directly.
# ============================================================================

class_name Codex
extends RefCounted

# ---------------------------------------------------------------------------
# RARITY TIERS
# ---------------------------------------------------------------------------
# An enum for the rarity tiers. The order matters: higher = rarer.
# We use these for display sorting and visual treatment later.

enum Rarity {
	COMMON,     ## Easily bred, mediocre traits (total trait score < 2.0)
	UNCOMMON,   ## Decent traits (total trait score 2.0-2.5)
	RARE,       ## Good traits or mutations (total trait score 2.5-3.0)
	LEGENDARY,  ## Exceptional traits (total trait score 3.0-3.5)
	MYTHIC,     ## Special events only (total trait score > 3.5 -- very rare)
}

# ---------------------------------------------------------------------------
# CODEX ENTRY
# ---------------------------------------------------------------------------
# A CodexEntry stores a strain plus metadata about its codex history.
# We don't just store the strain itself because we want to track additional
# info like how many times it was bred, and potentially a different display
# name or notes later.

# We use a simple Dictionary for each entry rather than a custom class.
# This keeps the codex lightweight and easy to serialize (save to disk).
# Each entry is:
# {
#   "strain": Strain,           # The strain data
#   "breed_count": int,         # How many times used as a parent
#   "rarity": Rarity,           # Calculated rarity tier
#   "first_seen": String,       # Date first discovered
# }

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------

var entries: Array[Dictionary] = []  ## All codex entries
var discovered_count: int = 0         ## Total unique strains discovered

# ---------------------------------------------------------------------------
# ADDING STRAINS TO THE CODEX
# ---------------------------------------------------------------------------

## Adds a strain to the codex if it hasn't been added before.
## Each strain is only added once (by name). If the strain is already
## in the codex, this does nothing (it's a duplicate discovery).
## Returns the index of the entry (new or existing).
func add_strain(strain: Strain) -> int:
	# Check if this strain is already in the codex (by name)
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var existing: Strain = entry["strain"]
		if existing.strain_name == strain.strain_name:
			# Already discovered -- don't add a duplicate
			return i

	# New discovery! Create a codex entry
	var rarity: Rarity = calculate_rarity(strain)
	var entry: Dictionary = {
		"strain": strain,
		"breed_count": 0,
		"rarity": rarity,
		"first_seen": strain.discovery_date,
	}
	entries.append(entry)
	discovered_count += 1
	return entries.size() - 1


## Increments the breed count for a strain in the codex.
## Called when a strain is used as a parent in breeding.
func increment_breed_count(strain: Strain) -> void:
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var existing: Strain = entry["strain"]
		if existing.strain_name == strain.strain_name:
			entry["breed_count"] += 1
			return


# ---------------------------------------------------------------------------
# RARITY CALCULATION
# ---------------------------------------------------------------------------

## Calculates the rarity tier for a strain based on its total trait quality.
# The idea: rarer strains have higher total trait scores.
# A "perfect" strain with all traits at 1.0 would have a score of 5.0
# (5 traits * 1.0 each). The seed strain (total ~2.5) is Common.
#
# Thresholds are tunable -- these are starting values for game balance.
# We also bump up the rarity if the strain has a personality (they're
# less common than basic strains).
func calculate_rarity(strain: Strain) -> Rarity:
	# Sum all 5 core traits
	var total_score: float = strain.stealth + strain.speed + strain.payload + strain.resilience + strain.stability

	# Having a personality trait adds value -- they're less common
	if strain.personality != Strain.Personality.NONE:
		total_score += 0.3

	# Higher generation strains have been bred more, suggesting investment
	# This doesn't affect score directly, but we give a small bonus
	# to generation 3+ strains (they've survived multiple breeding cycles)
	if strain.generation >= 3:
		total_score += 0.1

	# Determine rarity tier based on total score
	# These thresholds are game balance knobs you can tune!
	# The seed strain (stealth 0.4 + speed 0.5 + payload 0.3 + resilience 0.5
	# + stability 0.8 = 2.5 total) should be Common -- it's the starter.
	# A "perfect" strain (all 1.0) would score 5.0 -> Mythic.
	if total_score < 2.5:
		return Rarity.COMMON
	elif total_score < 3.0:
		return Rarity.UNCOMMON
	elif total_score < 3.5:
		return Rarity.RARE
	elif total_score < 4.0:
		return Rarity.LEGENDARY
	else:
		return Rarity.MYTHIC


# ---------------------------------------------------------------------------
# QUERY FUNCTIONS
# ---------------------------------------------------------------------------

## Returns the total number of strains discovered.
func get_count() -> int:
	return entries.size()


## Returns the count of strains at a specific rarity tier.
func get_count_by_rarity(rarity: Rarity) -> int:
	var count: int = 0
	for entry in entries:
		if entry["rarity"] == rarity:
			count += 1
	return count


## Returns a formatted string for the rarity name (for UI display).
func get_rarity_name(rarity: Rarity) -> String:
	match rarity:
		Rarity.COMMON:
			return "Common"
		Rarity.UNCOMMON:
			return "Uncommon"
		Rarity.RARE:
			return "Rare"
		Rarity.LEGENDARY:
			return "Legendary"
		Rarity.MYTHIC:
			return "Mythic"
		_:
			return "Unknown"


## Returns a color for the rarity tier (for UI display).
# NOTE: We're NOT using standard RPG rarity colors (grey/blue/purple/gold/orange).
# Instead we use the dark biological palette from the design doc.
# Rarity is communicated through intensity, not the standard cliché colors.
func get_rarity_color(rarity: Rarity) -> Color:
	match rarity:
		Rarity.COMMON:
			return Color(0.4, 0.4, 0.4)       # Ashen grey -- mundane
		Rarity.UNCOMMON:
			return Color(0.5, 0.6, 0.4)       # Sickly green -- interesting
		Rarity.RARE:
			return Color(0.6, 0.5, 0.7)       # Bruised purple -- noteworthy
		Rarity.LEGENDARY:
			return Color(0.8, 0.3, 0.3)       # Deep crimson -- dangerous
		Rarity.MYTHIC:
			return Color(0.9, 0.8, 0.3)       # Bile yellow -- otherworldly
		_:
			return Color(0.5, 0.5, 0.5)


## Returns all entries sorted by rarity (highest first), then by name.
func get_entries_sorted_by_rarity() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = entries.duplicate(true)

	# Sort by rarity descending (mythic first), then by name
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["rarity"] != b["rarity"]:
			return a["rarity"] > b["rarity"]
		return a["strain"].strain_name < b["strain"].strain_name
	)
	return sorted


## Returns a summary string of the codex for display.
## Shows total discovered + breakdown by rarity.
func get_summary() -> String:
	if entries.is_empty():
		return "Codex: Empty (0 discovered)"

	var text: String = "CODEX (%d discovered)\n" % discovered_count
	text += "Common: %d | Uncommon: %d | Rare: %d\n" % [
		get_count_by_rarity(Rarity.COMMON),
		get_count_by_rarity(Rarity.UNCOMMON),
		get_count_by_rarity(Rarity.RARE)
	]
	text += "Legendary: %d | Mythic: %d" % [
		get_count_by_rarity(Rarity.LEGENDARY),
		get_count_by_rarity(Rarity.MYTHIC)
	]
	return text


## Returns a detailed entry string for a single codex entry.
func get_entry_details(index: int) -> String:
	if index < 0 or index >= entries.size():
		return "Invalid entry"

	var entry: Dictionary = entries[index]
	var strain: Strain = entry["strain"]
	var rarity: Rarity = entry["rarity"]
	var rarity_name: String = get_rarity_name(rarity)

	var text: String = "%s\n" % strain.strain_name
	text += "Rarity: %s | Gen: %d | Personality: %s\n" % [
		rarity_name, strain.generation, strain.get_personality_label()
	]
	text += "Stealth: %.0f%% | Speed: %.0f%% | Payload: %.0f%%\n" % [
		strain.stealth * 100, strain.speed * 100, strain.payload * 100
	]
	text += "Resilience: %.0f%% | Stability: %.0f%%\n" % [
		strain.resilience * 100, strain.stability * 100
	]
	text += "Discovered: %s\n" % strain.discovery_date
	text += "Times bred: %d\n" % entry["breed_count"]
	text += "Income: %.1f/sec | Heat: %.1f/sec" % [
		strain.get_income_per_second(), strain.get_heat_per_second()
	]
	return text


## Clears all entries (used when starting a new game).
func clear() -> void:
	entries.clear()
	discovered_count = 0