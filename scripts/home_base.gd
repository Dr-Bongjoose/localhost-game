# ============================================================================
# home_base.gd - The Home Base Defense System
# ============================================================================
# Your containment facility is your home base. Specimens assigned as defenders
# protect it from incoming attacks. Successful defenses earn data -- this is
# the "safe income" that replaces the old idle income mechanic.
#
# WHY THIS EXISTS:
# Previously, idle specimens earned passive income for no reason. The player
# said that felt meaningless. Now, contained specimens earn ZERO by default.
# But if you ASSIGN them as defenders, they actively protect your base and
# earn data from successful defenses. This gives the player a real decision:
# "Do I keep this specimen as a defender (safe income) or deploy it as an
# attacker to a zone (high income, high risk)?"
#
# HOW IT WORKS:
# 1. The player assigns specimens as defenders (up to HOME_BASE_CAPACITY)
# 2. An attack timer counts down. When it fires, the base gets attacked.
# 3. Attack strength is random, scaled by global heat (more heat = stronger)
# 4. Each defender rolls resilience + luck vs attack strength
# 5. Surviving defenders earn data = attack_strength * resilience * reward_multiplier
# 6. If ALL defenders fail (or no defenders), it's a breach -- you lose data
# 7. Attack frequency scales with heat: quiet = 60s, aggressive = 15s
#
# THE MATH:
# - attack_strength: random 0.1 to 0.5, + heat * 0.01 (clamped to 0.9 max)
#   At 0 heat: attacks are 0.1-0.5 strength (easy)
#   At 50 heat: attacks are 0.1-1.0 strength (dangerous)
#   At 100 heat: attacks are 0.1-1.5 strength (clamped to 0.9, brutal)
# - defender_roll: resilience + randf(0, 0.3) (same luck factor as zone raids)
# - survived: defender_roll >= attack_strength
# - data_reward per surviving defender: attack_strength * resilience * 50
#   Weak attack (0.2), weak defender (0.3): 0.2 * 0.3 * 50 = 3 data
#   Medium attack (0.5), tough defender (0.7): 0.5 * 0.7 * 50 = 17.5 data
#   Strong attack (0.8), tough defender (0.8): 0.8 * 0.8 * 50 = 32 data
# - breach penalty (all defenders fail or no defenders): lose 10% of current data
# ============================================================================

class_name HomeBase
extends RefCounted

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

## How many specimens can be assigned as defenders at once.
const HOME_BASE_CAPACITY: int = 3

## Multiplier for data reward calculation.
## Was 50 -- too low (defense earned 20-50x less than zone income).
## At 500: a resilience 0.5 bug surviving a 0.3 attack earns 75 data.
## That's comparable to a weak zone deployment, making defense viable.
const REWARD_MULTIPLIER: float = 500.0

## Base attack interval (seconds) when heat is 0.
const ATTACK_INTERVAL_BASE: float = 60.0

## Minimum attack interval (seconds) at maximum heat.
const ATTACK_INTERVAL_MIN: float = 15.0

## Maximum fraction of current data lost on a breach.
const BREACH_PENALTY: float = 0.10

## Maximum attack strength (clamped even at extreme heat).
const MAX_ATTACK_STRENGTH: float = 0.9

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------

## Specimens currently assigned as defenders (Array of Strain objects).
## These are NOT deployed to zones -- they're at home base.
var defenders: Array[Strain] = []

## Timer counting down to the next attack (seconds).
var attack_timer: float = 0.0

## The interval for the next attack (calculated from heat).
var attack_interval: float = ATTACK_INTERVAL_BASE

## Accumulated data earned from defenses since last reset (for display).
var defense_data_earned: float = 0.0

## Total attacks resisted (for display/stats).
var attacks_resisted: int = 0

## Total breaches suffered (for display/stats).
var breaches_suffered: int = 0

# ---------------------------------------------------------------------------
# DEFENDER MANAGEMENT
# ---------------------------------------------------------------------------

## Assigns a specimen as a defender. Returns true if successful.
## Fails if the base is at capacity or the specimen is already a defender
## or already deployed to a zone (can't be both attacker and defender).
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
# ATTACK TIMER
# ---------------------------------------------------------------------------

## Calculates the attack interval based on global heat.
## At 0 heat: 60 seconds between attacks (quiet)
## At 50 heat: 30 seconds (moderate)
## At 100+ heat: 15 seconds (under siege)
## Formula: interval = max(MIN, BASE - heat * 0.45)
func calculate_attack_interval(heat: float) -> float:
	return maxf(ATTACK_INTERVAL_MIN, ATTACK_INTERVAL_BASE - heat * 0.45)

## Updates the attack timer. Called from main.gd's _process().
## Returns true if an attack should trigger this tick, false otherwise.
## When true, main.gd calls resolve_attack() to process the results.
func tick(delta: float, global_heat: float) -> bool:
	# Update the interval based on current heat (it changes as heat rises/falls)
	attack_interval = calculate_attack_interval(global_heat)

	# Count down
	attack_timer += delta
	if attack_timer >= attack_interval:
		attack_timer = 0.0
		return true  # Attack triggers!
	return false

## Forces the attack timer to reset (used when loading a save).
func reset_timer() -> void:
	attack_timer = 0.0
	attack_interval = ATTACK_INTERVAL_BASE

# ---------------------------------------------------------------------------
# ATTACK RESOLUTION
# ---------------------------------------------------------------------------

## Resolves an attack on the home base.
## Returns a Dictionary with the results:
##   {
##     "breach": bool,           # True if all defenders failed (or no defenders)
##     "attack_strength": float, # How strong the attack was (0.1 to 0.9)
##     "defender_results": Array of Dictionaries, each:
##       {"strain": Strain, "survived": bool, "roll": float, "reward": float}
##     "total_reward": float,    # Total data earned from surviving defenders
##     "breach_penalty": float,  # Data lost if breach (0.0 if no breach)
##   }
##
## Parameters:
##   global_heat: current total_heat from main.gd (scales attack strength)
func resolve_attack(global_heat: float) -> Dictionary:
	# --- GENERATE ATTACK STRENGTH ---
	# Base random strength 0.1 to 0.5, plus heat scaling
	var base_strength: float = randf_range(0.1, 0.5)
	var heat_bonus: float = global_heat * 0.01
	var attack_strength: float = clampf(base_strength + heat_bonus, 0.1, MAX_ATTACK_STRENGTH)

	# --- RESOLVE EACH DEFENDER ---
	var defender_results: Array = []
	var total_reward: float = 0.0
	var any_survived: bool = false
	var survivors: Array[Strain] = []  # Track defenders that survive

	for strain in defenders:
		# Roll: resilience + random luck (same formula as zone raid survival)
		var roll: float = strain.resilience + randf_range(0.0, 0.3)
		var survived: bool = roll >= attack_strength

		# Data reward for surviving defenders
		var reward: float = 0.0
		if survived:
			reward = attack_strength * strain.resilience * REWARD_MULTIPLIER
			total_reward += reward
			any_survived = true
			survivors.append(strain)  # This defender lives to fight another day
		else:
			print("Defender %s overwhelmed! (roll %.2f vs attack %.2f)" % [strain.strain_name, roll, attack_strength])

		defender_results.append({
			"strain": strain,
			"survived": survived,
			"roll": roll,
			"reward": reward,
		})

	# Replace defenders array with only the survivors
	defenders = survivors

	# --- DETERMINE BREACH ---
	# A breach happens if NO defenders survived (including having zero defenders).
	# On breach, the player loses a fraction of their data.
	var breach: bool = not any_survived
	var breach_penalty: float = 0.0

	# Update stats
	if breach:
		breaches_suffered += 1
	else:
		attacks_resisted += 1
	defense_data_earned += total_reward

	return {
		"breach": breach,
		"attack_strength": attack_strength,
		"defender_results": defender_results,
		"total_reward": total_reward,
		"breach_penalty": breach_penalty,  # Calculated by main.gd (needs player_data)
	}

# ---------------------------------------------------------------------------
# DISPLAY / UI HELPERS
# ---------------------------------------------------------------------------

## Returns a summary string for the home base status display.
func get_summary() -> String:
	var text: String = "HOME BASE\n"
	text += "Defenders: %d/%d\n" % [defenders.size(), HOME_BASE_CAPACITY]

	# Show next attack timer
	var time_left: float = maxf(0.0, attack_interval - attack_timer)
	text += "Next attack: %.0fs\n" % time_left

	if defenders.is_empty():
		text += "WARNING: No defenders! Breaches will occur."
	else:
		text += "Defending:\n"
		for s in defenders:
			text += "  %s (Resilience: %.0f%%)\n" % [s.strain_name, s.resilience * 100]

	return text

## Returns a short status string for the containment view.
func get_short_status() -> String:
	return "Defenders: %d/%d | Next attack: %.0fs" % [
		defenders.size(), HOME_BASE_CAPACITY,
		maxf(0.0, attack_interval - attack_timer)
	]

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
		"attack_timer": attack_timer,
		"attack_interval": attack_interval,
		"defense_data_earned": defense_data_earned,
		"attacks_resisted": attacks_resisted,
		"breaches_suffered": breaches_suffered,
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
	attack_timer = data.get("attack_timer", 0.0)
	attack_interval = data.get("attack_interval", ATTACK_INTERVAL_BASE)
	defense_data_earned = data.get("defense_data_earned", 0.0)
	attacks_resisted = data.get("attacks_resisted", 0)
	breaches_suffered = data.get("breaches_suffered", 0)