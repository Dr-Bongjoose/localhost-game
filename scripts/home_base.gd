# ============================================================================
# home_base.gd - The Home Base Defense System (Passive + Active Boost)
# ============================================================================
# Your containment facility is your home base. Specimens assigned as defenders
# protect it and earn passive income. You can also trigger an active defense
# boost when you choose to engage.
#
# PASSIVE INCOME (always on when defenders assigned):
# - Each defender earns data/sec = resilience * 0.5 * zone_data_value_base
# - No risk, no heat generation, no attention required
# - Replaces the old "idle income = 0" design — defenders give you a reason
#   to keep some strains home instead of deploying everything
#
# ACTIVE BOOST: "Activate Perimeter" (player-triggered, on cooldown)
# - Click when YOU want to engage
# - Cooldown scales with global heat (more heat = longer cooldown)
# - Big one-time data payout based on defender strength + heat level
# - Heat also increases chance of a "breach event" during the boost
#   (defenders take stability damage, but you still get the payout)
# - If no defenders assigned: button is disabled (no free boost)
#
# WHY THIS RESPECTS PLAYER TIME:
# - Passive income ticks away whether you're watching or not
# - Active boost is OPTIONAL — you click it when you're playing actively
# - No timer forcing you to check the game
# - Heat makes the boost stronger (risk/reward) but also longer cooldown
#   (natural pacing — you can't spam it when things are hot)
# ============================================================================

class_name HomeBase
extends RefCounted

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

## How many specimens can be assigned as defenders at once.
const HOME_BASE_CAPACITY: int = 3

## Base passive income per defender per second per resilience point.
## At resilience 0.5: 0.5 * 0.5 = 0.25 data/sec per defender.
## 3 defenders at 0.5 resilience = 0.75 data/sec passive.
## Compare to zone deployment: weak strain in Consumer zone = ~2 data/sec.
## So passive is meaningful but zones are still better for active play.
const PASSIVE_INCOME_PER_RESILIENCE: float = 0.5

## Base cooldown for Activate Perimeter (seconds) at 0 heat.
const PERIMETER_BASE_COOLDOWN: float = 30.0

## Maximum cooldown at extreme heat (seconds).
const PERIMETER_MAX_COOLDOWN: float = 180.0

## Heat scaling factor for cooldown.
## At 0 heat: 30s. At 50 heat: 30 + 50*3 = 180s (capped).
const PERIMETER_HEAT_COOLDOWN_SCALE: float = 3.0

## Base payout multiplier for Activate Perimeter.
## Payout = sum(defender_resilience) * heat_multiplier * this_constant
const PERIMETER_BASE_PAYOUT: float = 100.0

## Heat multiplier on payout: 1.0 + heat * 0.02
## At 0 heat: 1.0x. At 50 heat: 2.0x. At 100 heat: 3.0x.
const PERIMETER_HEAT_PAYOUT_SCALE: float = 0.02

## Chance of a "breach event" during Activate Perimeter.
## Base 5% + heat * 0.1%. At 50 heat: 10%. At 100 heat: 15%.
## If breach occurs, each defender takes stability damage (0.05-0.15).
## This is the risk of pushing during high heat.
const PERIMETER_BREACH_BASE_CHANCE: float = 0.05
const PERIMETER_BREACH_HEAT_SCALE: float = 0.001

## Stability damage range on breach.
const PERIMETER_STABILITY_DAMAGE_MIN: float = 0.05
const PERIMETER_STABILITY_DAMAGE_MAX: float = 0.15

## Passive income tick rate (seconds) - how often we add passive income.
const PASSIVE_TICK_RATE: float = 1.0

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------

## Specimens currently assigned as defenders (Array of Strain objects).
## These are NOT deployed to zones — they're at home base.
var defenders: Array[Strain] = []

## Timer for passive income ticks.
var _passive_timer: float = 0.0

## Cooldown timer for Activate Perimeter.
var _perimeter_cooldown: float = 0.0

## Whether the Activate Perimeter button is currently on cooldown.
var _perimeter_on_cooldown: bool = false

## Accumulated passive income earned since last reset (for display).
var passive_data_earned: float = 0.0

## Total perimeter activations (for stats).
var perimeter_activations: int = 0

## Total breaches suffered during perimeter activation.
var perimeter_breaches: int = 0

# ---------------------------------------------------------------------------
# DEFENDER MANAGEMENT
# ---------------------------------------------------------------------------

## Assigns a specimen as a defender. Returns true if successful.
## Fails if base is at capacity or specimen is already a defender
## or already deployed to a zone (checked in main.gd).
func assign_defender(strain: Strain) -> bool:
	if defenders.size() >= HOME_BASE_CAPACITY:
		return false
	if defenders.has(strain):
		return false
	defenders.append(strain)
	return true

## Recalls a specimen from defender duty. Returns true if it was a defender.
func recall_defender(strain: Strain) -> bool:
	var idx: int = defenders.find(strain)
	if idx == -1:
		return false
	defenders.remove_at(idx)
	return true

## Checks if a specimen is currently assigned as a defender.
func is_defender(strain: Strain) -> bool:
	return defenders.has(strain)

## Returns true if the base has no defenders.
func is_empty() -> bool:
	return defenders.is_empty()

## Returns true if all defender slots are full.
func is_full() -> bool:
	return defenders.size() >= HOME_BASE_CAPACITY

## Returns the number of free defender slots.
func get_free_slots() -> int:
	return HOME_BASE_CAPACITY - defenders.size()

# ---------------------------------------------------------------------------
# PASSIVE INCOME
# ---------------------------------------------------------------------------

## Called from main.gd _process(delta). Handles passive income ticks.
func tick_passive(delta: float) -> float:
	if defenders.is_empty():
		return 0.0

	_passive_timer += delta
	if _passive_timer < PASSIVE_TICK_RATE:
		return 0.0

	_passive_timer = 0.0

	# Calculate passive income: sum of (resilience * PASSIVE_INCOME_PER_RESILIENCE)
	var total_income: float = 0.0
	for strain in defenders:
		total_income += strain.resilience * PASSIVE_INCOME_PER_RESILIENCE

	passive_data_earned += total_income
	return total_income

## Returns current passive income per second (for UI display).
func get_passive_income_per_second() -> float:
	if defenders.is_empty():
		return 0.0
	var total: float = 0.0
	for strain in defenders:
		total += strain.resilience * PASSIVE_INCOME_PER_RESILIENCE
	return total

# ---------------------------------------------------------------------------
# ACTIVATE PERIMETER (Active Boost)
# ---------------------------------------------------------------------------

## Returns the current cooldown remaining (0.0 if ready).
func get_perimeter_cooldown_remaining() -> float:
	return max(0.0, _perimeter_cooldown)

## Returns true if Activate Perimeter is ready to use.
func is_perimeter_ready() -> bool:
	return _perimeter_cooldown <= 0.0 and not defenders.is_empty()

## Called from main.gd _process to tick down the perimeter cooldown.
func tick_perimeter_cooldown(delta: float) -> void:
	if _perimeter_cooldown > 0.0:
		_perimeter_cooldown -= delta
		if _perimeter_cooldown < 0.0:
			_perimeter_cooldown = 0.0

## Calculates the cooldown based on current global heat.
## Higher heat = longer cooldown (natural pacing).
func calculate_perimeter_cooldown(global_heat: float) -> float:
	var cooldown: float = PERIMETER_BASE_COOLDOWN + global_heat * PERIMETER_HEAT_COOLDOWN_SCALE
	return clampf(cooldown, PERIMETER_BASE_COOLDOWN, PERIMETER_MAX_COOLDOWN)

## Triggers the Activate Perimeter active boost.
## Returns a Dictionary with results for UI display:
##   {
##     "success": bool,
##     "payout": float,
##     "breach_occurred": bool,
##     "breach_details": Array of { "strain": Strain, "stability_lost": float },
##     "cooldown_set": float
##   }
## Caller (main.gd) should pass current global_heat for scaling.
func activate_perimeter(global_heat: float) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"payout": 0.0,
		"breach_occurred": false,
		"breach_details": [],
		"cooldown_set": 0.0
	}

	# Can't activate if on cooldown or no defenders
	if not is_perimeter_ready():
		return result

	# --- CALCULATE PAYOUT ---
	# Base: sum of defender resilience * PERIMETER_BASE_PAYOUT
	var total_resilience: float = 0.0
	for strain in defenders:
		total_resilience += strain.resilience

	# Heat multiplier: 1.0 + heat * PERIMETER_HEAT_PAYOUT_SCALE
	var heat_multiplier: float = 1.0 + global_heat * PERIMETER_HEAT_PAYOUT_SCALE

	var payout: float = total_resilience * PERIMETER_BASE_PAYOUT * heat_multiplier
	result["payout"] = payout

	# --- CHECK FOR BREACH ---
	# Chance: base + heat * scale
	var breach_chance: float = PERIMETER_BREACH_BASE_CHANCE + global_heat * PERIMETER_BREACH_HEAT_SCALE
	breach_chance = clampf(breach_chance, 0.0, 0.5)  # Cap at 50%

	var breach_occurred: bool = randf() < breach_chance
	result["breach_occurred"] = breach_occurred

	var breach_details: Array = []
	if breach_occurred:
		perimeter_breaches += 1
		# Each defender takes stability damage
		for strain in defenders:
			var damage: float = randf_range(PERIMETER_STABILITY_DAMAGE_MIN, PERIMETER_STABILITY_DAMAGE_MAX)
			var old_stability: float = strain.stability
			strain.stability = max(0.0, strain.stability - damage)
			breach_details.append({
				"strain": strain,
				"stability_lost": damage,
				"old_stability": old_stability,
				"new_stability": strain.stability
			})
	result["breach_details"] = breach_details

	# --- SET COOLDOWN ---
	var cooldown: float = calculate_perimeter_cooldown(global_heat)
	_perimeter_cooldown = cooldown
	result["cooldown_set"] = cooldown

	perimeter_activations += 1
	result["success"] = true

	return result

# ---------------------------------------------------------------------------
# UI / DISPLAY HELPERS
# ---------------------------------------------------------------------------

## Returns a summary string for the home base panel.
func get_summary(global_heat: float) -> String:
	var text: String = "HOME BASE DEFENSE\n"
	text += "Defenders: %d/%d\n" % [defenders.size(), HOME_BASE_CAPACITY]
	text += "Passive Income: %.2f data/sec\n" % get_passive_income_per_second()
	text += "Total Passive Earned: %.1f data\n" % passive_data_earned
	text += "\n"
	text += "ACTIVATE PERIMETER\n"
	if defenders.is_empty():
		text += "Assign defenders to enable\n"
	elif _perimeter_cooldown > 0.0:
		text += "Cooldown: %.0fs\n" % _perimeter_cooldown
	else:
		text += "READY — Click to activate\n"
		# Show estimated payout
		var total_resilience: float = 0.0
		for strain in defenders:
			total_resilience += strain.resilience
		var heat_mult: float = 1.0 + global_heat * PERIMETER_HEAT_PAYOUT_SCALE
		var est_payout: float = total_resilience * PERIMETER_BASE_PAYOUT * heat_mult
		text += "Est. Payout: %.0f data (%.1fx heat mult)\n" % [est_payout, heat_mult]
		var breach_chance: float = PERIMETER_BREACH_BASE_CHANCE + global_heat * PERIMETER_BREACH_HEAT_SCALE
		breach_chance = clampf(breach_chance, 0.0, 0.5)
		if breach_chance > 0.01:
			text += "Breach Risk: %.0f%%\n" % (breach_chance * 100)

	text += "\nStats: %d activations, %d breaches" % [perimeter_activations, perimeter_breaches]
	return text

## Returns a short status for the containment view header.
func get_short_status(global_heat: float) -> String:
	if defenders.is_empty():
		return "Home Base: Empty (no passive income)"
	var passive: float = get_passive_income_per_second()
	var perimeter_status: String = "Ready" if is_perimeter_ready() else "Cooldown: %.0fs" % _perimeter_cooldown
	return "Home Base: %d defenders | %.2f data/sec passive | Perimeter: %s" % [defenders.size(), passive, perimeter_status]

## Resets home base state (used on new game).
func reset() -> void:
	defenders.clear()
	_passive_timer = 0.0
	_perimeter_cooldown = 0.0
	passive_data_earned = 0.0
	perimeter_activations = 0
	perimeter_breaches = 0


# ---------------------------------------------------------------------------
# SERIALIZATION (for save system)
# ---------------------------------------------------------------------------

## Returns a Dictionary with the names of assigned defenders (for saving).
## We save names, not objects, same as zones -- reconnected on load.
func serialize() -> Dictionary:
	var defender_names: Array = []
	for strain in defenders:
		defender_names.append(strain.strain_name)
	return {
		"defender_names": defender_names,
		"_passive_timer": _passive_timer,
		"_perimeter_cooldown": _perimeter_cooldown,
		"passive_data_earned": passive_data_earned,
		"perimeter_activations": perimeter_activations,
		"perimeter_breaches": perimeter_breaches,
	}

## Reconnects defenders after loading. Finds specimens by name in the
## player's collection and reassigns them as defenders.
func deserialize(data: Dictionary, player_strains: Array) -> void:
	defenders.clear()
	var defender_names: Array = data.get("defender_names", [])
	for name in defender_names:
		for strain in player_strains:
			if strain.strain_name == name:
				defenders.append(strain)
				break
	_passive_timer = data.get("_passive_timer", 0.0)
	_perimeter_cooldown = data.get("_perimeter_cooldown", 0.0)
	passive_data_earned = data.get("passive_data_earned", 0.0)
	perimeter_activations = data.get("perimeter_activations", 0)
	perimeter_breaches = data.get("perimeter_breaches", 0)