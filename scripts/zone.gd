# ============================================================================
# zone.gd - The Zone System
# ============================================================================
# Zones are locations on the internet where you deploy strains to earn data.
# Each zone type has a different risk/reward profile:
#
#   CONSUMER NETWORK  -- Low security, low payout. Safe starting zone.
#   CORPORATE SERVER  -- Medium security, medium payout. Need decent stealth.
#   GOVERNMENT NET    -- High security, high payout. Very risky but rewarding.
#   DARK WEB NODE     -- Unpredictable. Can be great or terrible. Chaotic.
#
# HOW ZONES WORK:
# - You deploy a strain from your collection to a zone
# - The strain earns bonus income (base income * zone's data_value multiplier)
# - The strain also generates heat in that zone, modified by the zone's
#   detection_rate and the strain's stealth
# - If heat in a zone exceeds its detection_threshold, a "raid check" happens:
#   the strain rolls against its resilience to survive. If it fails, it's
#   destroyed (removed from the zone, but stays in the codex).
# - You can recall a strain from a zone at any time (no cost, instant)
# - A strain can only be in one zone at a time
#
# This gives the player their first real strategic decision:
# "Do I send my best strain to the Government Network for 3x income,
#  knowing it might get destroyed?"
# ============================================================================

class_name Zone
extends RefCounted

# ---------------------------------------------------------------------------
# ZONE TYPES (enum)
# ---------------------------------------------------------------------------
# Each type has fixed base properties defined in _init_type_properties().

enum ZoneType {
	CONSUMER,     ## Low security, low payout. Safe. Good for beginners.
	CORPORATE,     ## Medium security, medium payout. Need decent stealth.
	GOVERNMENT,   ## High security, high payout. Very risky.
	DARK_WEB,     ## Unpredictable. Variable everything.
}

# ---------------------------------------------------------------------------
# PROPERTIES
# ---------------------------------------------------------------------------

var zone_type: ZoneType = ZoneType.CONSUMER
var zone_name: String = "Unknown Zone"

## How much the zone multiplies a strain's base income.
## 1.0 = same as being idle (home network). 2.0 = double income. Etc.
var data_value: float = 1.0

## How fast heat rises while a strain is deployed here. Multiplier on the
## strain's base heat generation. 0.5 = heat rises half as fast. 2.0 = double.
var detection_rate: float = 1.0

## Heat threshold before a raid check happens. When accumulated zone heat
## exceeds this, the deployed strain must pass a resilience check or be
## destroyed. Higher = safer zone.
var detection_threshold: float = 50.0

## How many strains can be deployed here simultaneously.
var capacity: int = 2

## The strains currently deployed in this zone (Array of Strain objects).
var deployed_strains: Array[Strain] = []

## Current heat level in this zone. Rises from deployed strains, decays
## when strains are recalled or over time.
var zone_heat: float = 0.0

## Whether this zone is currently "locked" (player hasn't unlocked it yet).
## Phase 1: all zones unlocked from the start. Phase 2 will add unlock costs.
var locked: bool = false

# ---------------------------------------------------------------------------
# FACTORY: CREATE ZONES BY TYPE
# ---------------------------------------------------------------------------

## Creates a zone of the specified type with the correct base properties.
## This is a static factory method -- you call Zone.create(Zone.ZoneType.GOVERNMENT)
## rather than zone_instance.create().
static func create(type: ZoneType) -> Zone:
	var z = new()
	z.zone_type = type
	z._init_type_properties()
	return z

## Sets up the zone's properties based on its type.
## This is called automatically by create(). Each zone type has different
## values tuned for game balance. These are KNOBS you can adjust to change
## the feel of the game:
## - Higher data_value = zones pay more (easier game)
## - Higher detection_rate = zones are more dangerous (harder game)
## - Lower detection_threshold = raids happen sooner (more tense)
func _init_type_properties() -> void:
	match zone_type:
		ZoneType.CONSUMER:
			zone_name = "Consumer Network"
			data_value = 1.5         # 50% bonus income over idle
			detection_rate = 0.5      # Heat rises slowly
			detection_threshold = 80.0  # Tolerant zone, raids are rare
			capacity = 3             # Can hold 3 strains

		ZoneType.CORPORATE:
			zone_name = "Corporate Server"
			data_value = 2.5         # 2.5x income
			detection_rate = 1.0      # Standard heat rate
			detection_threshold = 50.0  # Moderate raid risk
			capacity = 2

		ZoneType.GOVERNMENT:
			zone_name = "Government Network"
			data_value = 4.0         # 4x income -- very lucrative
			detection_rate = 2.0      # Heat rises fast
			detection_threshold = 30.0  # Low threshold = raids happen quickly
			capacity = 1             # Only room for 1 strain

		ZoneType.DARK_WEB:
			zone_name = "Dark Web Node"
			# Dark Web is chaotic -- values are randomized each time you create one
			data_value = randf_range(1.0, 5.0)
			detection_rate = randf_range(0.3, 3.0)
			detection_threshold = randf_range(20.0, 80.0)
			capacity = 2

# ---------------------------------------------------------------------------
# DEPLOYMENT
# ---------------------------------------------------------------------------

## Attempts to deploy a strain to this zone.
## Returns true if successful, false if the zone is full or the strain is
## already deployed somewhere (we check that in main.gd, not here -- but
## we do check capacity).
func deploy(strain: Strain) -> bool:
	if locked:
		return false
	if deployed_strains.size() >= capacity:
		return false
	deployed_strains.append(strain)
	return true

## Recalls (removes) a strain from this zone.
## Returns true if the strain was found and removed, false if it wasn't here.
func recall(strain: Strain) -> bool:
	var idx: int = deployed_strains.find(strain)
	if idx == -1:
		return false
	deployed_strains.remove_at(idx)
	return true

## Checks if a specific strain is deployed in this zone.
func has_strain(strain: Strain) -> bool:
	return deployed_strains.find(strain) != -1

## Returns the number of free slots in this zone.
func get_free_slots() -> int:
	return capacity - deployed_strains.size()

## Returns true if the zone is at capacity (no free slots).
func is_full() -> bool:
	return deployed_strains.size() >= capacity

# ---------------------------------------------------------------------------
# ZONE TICKING (called from main.gd's _process)
# ---------------------------------------------------------------------------

## Called every frame by main.gd. Updates zone heat and checks for raids.
## Returns a Dictionary with raid results:
##   {"raids": Array of Dictionaries, each with {"strain": Strain, "survived": bool}}
## If no raids happened, the array is empty.
func tick(delta: float) -> Dictionary:
	var raid_results: Array = []

	if deployed_strains.is_empty():
		# No strains = no heat generation, but heat still decays
		zone_heat *= 1.0 - (0.02 * delta)  # 2% per second decay when empty
		if zone_heat < 0.01:
			zone_heat = 0.0
		return {"raids": raid_results}

	# --- HEAT GENERATION ---
	# Each deployed strain adds heat, modified by the zone's detection_rate
	# and the strain's stealth (high stealth = less heat)
	for strain in deployed_strains:
		var strain_heat: float = strain.get_heat_per_second()
		# Zone's detection_rate multiplies the strain's base heat
		# Stealth reduces heat in the zone (same as global, but per-zone)
		var effective_heat: float = strain_heat * detection_rate * (1.0 - strain.stealth * 0.5)
		zone_heat += effective_heat * delta

	# --- HEAT DECAY ---
	# Zone heat decays slowly even with strains deployed (represents the
	# strain's own efforts to stay hidden). 0.5% per second.
	zone_heat *= 1.0 - (0.005 * delta)

	# --- RAID CHECK ---
	# If heat exceeds the threshold, there's a chance of a raid each tick.
	# We don't raid every frame -- we use a probability check so raids feel
	# like events, not instant wipes.
	if zone_heat >= detection_threshold:
		# Raid probability: how far over threshold determines raid chance.
		# At exactly the threshold: 2% chance per second of a raid.
		# At 2x the threshold: 4% chance per second.
		var over_factor: float = zone_heat / detection_threshold
		var raid_chance: float = 0.02 * over_factor * delta  # per-second scaled by delta

		if randf() < raid_chance:
			# A raid happens! Pick a random deployed strain to target.
			# (In Phase 2, higher heat levels could target ALL strains.)
			var target: Strain = deployed_strains[randi_range(0, deployed_strains.size() - 1)]

			# Resilience check: the strain rolls its resilience vs the zone's
			# security level. The zone_security_factor is scaled so it's
			# comparable to resilience (0.0-1.0 range).
			# detection_rate ranges: 0.5 (Consumer) to 2.0 (Government)
			# We map it to a 0.3-0.8 survival difficulty range so that:
			#   - Consumer (det=0.5): factor=0.3, weak strains can survive
			#   - Corporate (det=1.0): factor=0.5, need decent resilience
			#   - Government (det=2.0): factor=0.8, need high resilience + luck
			# Dark Web is variable.
			var zone_security_factor: float = 0.2 + (detection_rate * 0.3)
			# Clamp to 0.1-0.9 so there's always a chance to survive or die
			zone_security_factor = clampf(zone_security_factor, 0.1, 0.9)

			# The strain rolls resilience + a small random bonus (luck)
			var strain_roll: float = target.resilience + randf_range(0.0, 0.3)

			var survived: bool = strain_roll >= zone_security_factor

			if not survived:
				# Strain is destroyed! Remove it from the zone.
				deployed_strains.erase(target)
				# Heat drops significantly after a successful raid (security calms down)
				zone_heat *= 0.3

			raid_results.append({"strain": target, "survived": survived})

			# After any raid (success or fail), heat drops a bit (security attention shifts)
			zone_heat *= 0.8

	return {"raids": raid_results}

# ---------------------------------------------------------------------------
# INCOME CALCULATION
# ---------------------------------------------------------------------------

## Returns the total income generated by all strains deployed in this zone.
## This is the sum of each strain's base income * the zone's data_value.
func get_zone_income() -> float:
	var total: float = 0.0
	for strain in deployed_strains:
		total += strain.get_income_per_second() * data_value
	return total

## Returns the total heat generated per second by all deployed strains.
## For display purposes (the actual heat accumulation happens in tick()).
func get_zone_heat_per_second() -> float:
	var total: float = 0.0
	for strain in deployed_strains:
		total += strain.get_heat_per_second() * detection_rate * (1.0 - strain.stealth * 0.5)
	return total

# ---------------------------------------------------------------------------
# DISPLAY / UI HELPERS
# ---------------------------------------------------------------------------

## Returns a string name for the zone type (for display).
func get_type_name() -> String:
	match zone_type:
		ZoneType.CONSUMER:
			return "Consumer Network"
		ZoneType.CORPORATE:
			return "Corporate Server"
		ZoneType.GOVERNMENT:
			return "Government Network"
		ZoneType.DARK_WEB:
			return "Dark Web Node"
		_:
			return "Unknown"

## Returns a short description of the zone's risk level.
func get_risk_label() -> String:
	match zone_type:
		ZoneType.CONSUMER:
			return "Low Risk"
		ZoneType.CORPORATE:
			return "Medium Risk"
		ZoneType.GOVERNMENT:
			return "High Risk"
		ZoneType.DARK_WEB:
			return "Unpredictable"
		_:
			return "Unknown"

## Returns a color for the zone's risk level (dark biological palette).
func get_risk_color() -> Color:
	match zone_type:
		ZoneType.CONSUMER:
			return Color(0.4, 0.6, 0.4)   # Muted green -- safe
		ZoneType.CORPORATE:
			return Color(0.7, 0.6, 0.3)   # Bile yellow -- caution
		ZoneType.GOVERNMENT:
			return Color(0.8, 0.3, 0.3)    # Deep crimson -- danger
		ZoneType.DARK_WEB:
			return Color(0.6, 0.4, 0.7)   # Bruised purple -- chaotic
		_:
			return Color(0.5, 0.5, 0.5)

## Returns a full summary string for the zone (for UI display).
func get_summary() -> String:
	var text: String = "%s (%s)\n" % [zone_name, get_risk_label()]
	text += "Payout: %.1fx | Detection: %.1fx | Threshold: %.0f\n" % [
		data_value, detection_rate, detection_threshold
	]
	text += "Capacity: %d/%d specimens\n" % [deployed_strains.size(), capacity]
	text += "Zone Heat: %.1f / %.0f\n" % [zone_heat, detection_threshold]
	if not deployed_strains.is_empty():
		text += "Deployed:\n"
		for s in deployed_strains:
			text += "  %s (Gen %d) - %.1f/sec\n" % [s.strain_name, s.generation, s.get_income_per_second() * data_value]
	else:
		text += "No strains deployed."
	return text

## Returns a short one-line status for the zone list.
func get_short_status() -> String:
	return "%s | %dx | %d/%d | Heat: %.0f/%.0f" % [
		zone_name, data_value, deployed_strains.size(), capacity,
		zone_heat, detection_threshold
	]