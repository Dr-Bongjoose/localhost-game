# ============================================================================
# breeding.gd - The Breeding System
# ============================================================================
# This script handles the logic of combining two strains into a new one.
# It's a "static" helper class -- it doesn't hold any state, it just has
# functions you call. Think of it as a laboratory procedure: you give it
# two parent strains, it gives you back a child strain.
#
# BREEDING RULES (Phase 2 -- now with NAMED MUTATION EVENTS):
# 1. Each trait of the child is a weighted average of the parents' traits,
#    biased toward the stronger parent (60% stronger, 40% weaker).
# 2. Every trait has a small random jitter (+/- 0.05) to make even identical
#    parents produce slightly different children.
# 3. Mutation chance is based on BOTH parents' stability:
#    Low stability (both parents) = high mutation chance
#    High stability (both parents) = low mutation chance
#    When a mutation triggers, it's not just a random trait shift -- it's
#    a NAMED EVENT (Trait Surge, Degradation, Inversion, Cascade, etc.)
#    with its own mechanical effects and flavor text.
# 4. The child's generation is max(parent_a.generation, parent_b.generation) + 1.
# 5. The child inherits a personality from one of the parents (random pick),
#    or if both parents have NONE, there's a small chance of a spontaneous
#    personality emerging.
# 6. Breeding costs data (currency). The cost goes up with generation.
#
# The mutation event info is stored on the child strain in `mutation_event`
# (a Dictionary) so the UI can display it in the discovery moment overlay.
# ============================================================================

class_name Breeding
extends RefCounted

# --------------------------------------------------------------------------- 
# MUTATION EVENT TYPES
# --------------------------------------------------------------------------- 
# Each mutation is a NAMED EVENT, not just an anonymous trait shift.
# This makes every breed a roll of the dice with dramatic outcomes.
# Events are weighted -- common ones happen often, rare ones are exciting.
#
# The weight determines how likely each event is relative to others.
# Higher weight = more common. We pick using weighted random selection:
#   1. Sum all weights
#   2. Pick a random number 0 to total_weight
#   3. Walk through the events, subtracting each weight until we hit 0
# This is the standard "roulette wheel" algorithm used in games everywhere.
#
# The event Dictionary stored on the child strain has:
#   "event_name": String  -- uppercase display name ("TRAIT SURGE")
#   "event_desc": String  -- flavor text for the UI
#   "event_color": Color  -- biological palette color for UI emphasis
#   "affected_traits": Array[String] -- which traits changed
#   "details": Dictionary  -- { trait_name: {"old": float, "new": float} }

enum MutationType {
	SURGE,            ## One trait jumps UP significantly (good)
	DEGRADE,          ## One trait drops significantly (bad)
	INVERSION,        ## A high trait goes low, or low goes high (dramatic)
	CASCADE,          ## 2-3 traits all shift in the same direction
	PERSONALITY_EMERGENCE, ## Strain gains a new personality neither parent had
	STABILITY_COLLAPSE,    ## Stability crashes -- future breeding goes wild
	HYPERGENESIS,     ## ALL traits shift up slightly (the jackpot)
}

# --------------------------------------------------------------------------- 
# BREEDING RISK MECHANICS (Phase 3)
# --------------------------------------------------------------------------- 
# Breeding carries risks beyond just mutation. These three mechanics add
# strategic depth: breeding is an investment with real risk.
#
# 1. BREEDING FAILURE: The attempt fails entirely. Data cost is lost,
#    no child produced. Chance increases with generation gap and low stability.
# 2. DEGRADED OFFSPRING: Child is produced but all traits are reduced by
#    10-20%. This represents a "runty" offspring. Mutation events can still
#    occur on degraded offspring (rare but possible).
# 3. GENETIC DAMAGE: One parent takes permanent stability damage from the
#    stress of breeding. This modifies the parent IN PLACE in the player's
#    collection -- a permanent scar on the parent strain.

# Result enum so main.gd can distinguish failure types
# SELF_BREEDING = tried to breed a strain with itself (UI prevents this)
# FAILURE = breeding attempt failed (data lost, no child)
# SUCCESS = child produced (may be degraded or have genetic damage to parent)
enum BreedResult {
	SUCCESS,
	SELF_BREEDING,
	FAILURE,
}

# Static vars to communicate breeding results back to main.gd
# Since breed() returns only the child (or null), we use static vars
# to communicate additional outcome info.
static var last_breed_result: BreedResult = BreedResult.SUCCESS
static var last_genetic_damage: Dictionary = {}  # {"parent_name": String, "stability_lost": float, "new_stability": float}

# Weight table -- how likely each event is when a mutation triggers.
# Total weight = 100, so weights are effectively percentages.
# SURGE and DEGRADATION are common (30 each = 60% of all mutations)
# INVERSION and CASCADE are uncommon (15 each = 30%)
# PERSONALITY_EMERGENCE and STABILITY_COLLAPSE are rare (5 each = 10%)
# HYPERGENESIS is very rare (5 = 5%) -- but it's 5 out of 100, not 5%
# because the total is 100, each point of weight = 1% chance.
const MUTATION_WEIGHTS: Dictionary = {
	MutationType.SURGE: 30,
	MutationType.DEGRADE: 30,
	MutationType.INVERSION: 15,
	MutationType.CASCADE: 15,
	MutationType.PERSONALITY_EMERGENCE: 5,
	MutationType.STABILITY_COLLAPSE: 5,
	MutationType.HYPERGENESIS: 5,
}

# ---------------------------------------------------------------------------
# BREEDING COST
# ---------------------------------------------------------------------------

## Returns the data cost to breed two strains.
## Higher generation strains are more expensive to breed.
## Formula: base_cost + max_generation * cost_per_gen
## Two gen-1 bugs: 200 + 1*100 = 300 data
## Two gen-3 bugs: 200 + 3*100 = 500 data
## Two gen-5 bugs: 200 + 5*100 = 700 data
## Each breed is a significant investment -- you need to deploy and earn
## before you can afford the next generation.
static func get_breed_cost(parent_a: Strain, parent_b: Strain) -> int:
	var max_gen: int = max(parent_a.generation, parent_b.generation)
	var base_cost: int = 200
	var cost_per_gen: int = 100
	return base_cost + max_gen * cost_per_gen

# ---------------------------------------------------------------------------
# MAIN BREEDING FUNCTION
# ---------------------------------------------------------------------------

## Combines two parent strains and returns a new child strain.
## Returns null if the parents are the same strain (you can't breed a strain
## with itself -- that would be cloning, not breeding), OR if the breeding
## attempt fails entirely (Breeding Failure risk mechanic).
## Check Breeding.last_breed_result after calling to distinguish:
##   SUCCESS = child produced (may be degraded, parent may have genetic damage)
##   SELF_BREEDING = tried to breed a strain with itself (UI prevents this)
##   FAILURE = breeding attempt failed (data lost, no child produced)
static func breed(parent_a: Strain, parent_b: Strain) -> Strain:
	# Reset the result vars for this breeding attempt
	last_breed_result = BreedResult.SUCCESS
	last_genetic_damage = {}

	# Step 1: Check self-breeding -> set last_breed_result = SELF_BREEDING, return null
	if parent_a == parent_b:
		push_error("Breeding: cannot breed a strain with itself!")
		last_breed_result = BreedResult.SELF_BREEDING
		return null

	# Step 2: Check breeding failure -> set last_breed_result = FAILURE, return null
	# Failure chance formula: base 5% + gen_gap * 5% + instability penalty
	# gen_gap = abs(parent_a.generation - parent_b.generation)
	# instability_penalty = (1.0 - avg_stability) * 0.10
	# Cap at 30% maximum (so breeding never feels hopeless)
	var gen_gap: int = abs(parent_a.generation - parent_b.generation)
	var avg_stability: float = (parent_a.stability + parent_b.stability) / 2.0
	var instability_penalty: float = (1.0 - avg_stability) * 0.10
	var failure_chance: float = 0.05 + (gen_gap * 0.05) + instability_penalty
	failure_chance = min(failure_chance, 0.30)  # Cap at 30%

	if randf() < failure_chance:
		last_breed_result = BreedResult.FAILURE
		return null

	# Step 3: Create child, inherit traits, roll mutations, inherit personality, set metadata, clamp traits
	var child = Strain.new()

	# --- TRAIT INHERITANCE ---
	# For each trait, the child gets a weighted average of both parents.
	# We bias toward the stronger parent: 60% from the stronger, 40% from weaker.
	# Then we add a small random jitter so children aren't perfectly predictable.

	child.stealth = _inherit_trait(parent_a.stealth, parent_b.stealth)
	child.speed = _inherit_trait(parent_a.speed, parent_b.speed)
	child.payload = _inherit_trait(parent_a.payload, parent_b.payload)
	child.resilience = _inherit_trait(parent_a.resilience, parent_b.resilience)
	child.stability = _inherit_trait(parent_a.stability, parent_b.stability)

	# --- MUTATION CHECK ---
	# The chance of mutation depends on both parents' stability.
	# If both parents have low stability, mutations are more likely.
	# The mutation_chance is 0.0 to 1.0 (a probability).
	var mutation_chance: float = _calculate_mutation_chance(parent_a, parent_b)

	# Roll for mutation -- randf() returns a random float 0.0 to 1.0
	# If the roll is below the mutation chance, a mutation occurs
	# We pass the child AND both parents so the mutation function can
	# make informed choices (e.g. Inversion flips the strongest trait).
	if randf() < mutation_chance:
		_apply_mutation(child, parent_a, parent_b)

	# --- PERSONALITY INHERITANCE ---
	child.personality = _inherit_personality(parent_a, parent_b)

	# --- METADATA ---
	# The child's generation is one higher than the highest parent generation
	child.generation = max(parent_a.generation, parent_b.generation) + 1

	# Generate a name based on generation
	# Gen 2 strains are "Worm-XXX", gen 3 are "Hybrid-XXX", gen 4+ are "Mutant-XXX"
	var prefix: String = _get_name_prefix(child.generation)
	var random_id: int = randi_range(1, 999)
	child.strain_name = "%s-%03d" % [prefix, random_id]

	# Set discovery date to today
	var date_dict: Dictionary = Time.get_date_dict_from_system()
	child.discovery_date = "%04d-%02d-%02d" % [date_dict["year"], date_dict["month"], date_dict["day"]]

	# Clamp all traits to valid range (0.0 to 1.0) after mutations
	# A mutation could push a trait above 1.0 or below 0.0, so we clamp
	child.stealth = clampf(child.stealth, 0.0, 1.0)
	child.speed = clampf(child.speed, 0.0, 1.0)
	child.payload = clampf(child.payload, 0.0, 1.0)
	child.resilience = clampf(child.resilience, 0.0, 1.0)
	child.stability = clampf(child.stability, 0.0, 1.0)

	# Step 4: Check degraded offspring -> if triggered, reduce all traits, set mutation_event
	# Chance: 12% base, modified by stability: + (1.0 - avg_stability) * 0.08
	# Example: 50% stability = 12% + 4% = 16% chance
	# When triggered: all 5 child traits multiplied by randf_range(0.80, 0.90) (10-20% reduction)
	# This check happens AFTER trait inheritance and mutation rolls, so mutations
	# can still occur on degraded offspring (rare but possible)
	var degraded_chance: float = 0.12 + (1.0 - avg_stability) * 0.08
	if randf() < degraded_chance:
		var reduction_factor: float = randf_range(0.80, 0.90)
		var details: Dictionary = {}
		var affected: Array[String] = []

		# Apply degradation to all 5 traits
		var all_traits: Array[String] = ["stealth", "speed", "payload", "resilience", "stability"]
		for trait_name in all_traits:
			var old_val: float = child.get(trait_name)
			var new_val: float = old_val * reduction_factor
			child.set(trait_name, new_val)
			details[trait_name] = {"old": old_val, "new": new_val}
			affected.append(trait_name)

		# Set mutation_event for the degraded offspring
		child.mutation_event = {
			"event_name": "DEGRADED OFFSPRING",
			"event_desc": "The offspring is runty -- all traits reduced.",
			"event_color": Color(0.5, 0.45, 0.4),  # Muddy brown
			"affected_traits": affected,
			"details": details,
		}

	# Step 5: Check genetic damage
	# Chance: 15% base
	# When triggered: pick one parent randomly (50/50), reduce their stability
	# by randf_range(0.05, 0.10) (5-10%)
	# This modifies the parent IN PLACE (the actual Strain object in player_strains)
	# Do NOT save this in mutation_event (that's for the child's event).
	# Instead, return info via last_genetic_damage Dictionary
	if randf() < 0.15:
		var damaged_parent: Strain
		if randf() < 0.5:
			damaged_parent = parent_a
		else:
			damaged_parent = parent_b

		var stability_lost: float = randf_range(0.05, 0.10)
		var old_stability: float = damaged_parent.stability
		damaged_parent.stability = max(0.0, damaged_parent.stability - stability_lost)

		last_genetic_damage = {
			"parent_name": damaged_parent.strain_name,
			"stability_lost": stability_lost,
			"new_stability": damaged_parent.stability,
		}

	# Step 6: Set last_breed_result = SUCCESS, return child
	last_breed_result = BreedResult.SUCCESS
	return child


# ---------------------------------------------------------------------------
# TRAIT INHERITANCE HELPER
# ---------------------------------------------------------------------------

## Combines two parent trait values into a child value.
## The stronger parent contributes 60%, the weaker parent 40%.
## A small random jitter (+/- 0.05) adds unpredictability.
static func _inherit_trait(value_a: float, value_b: float) -> float:
	# Figure out which parent is stronger (higher value) for this trait
	var stronger: float = max(value_a, value_b)
	var weaker: float = min(value_a, value_b)

	# Weighted average: 60% from stronger, 40% from weaker
	var inherited: float = (stronger * 0.6) + (weaker * 0.4)

	# Random jitter: add or subtract up to 0.05
	# randf_range(-0.05, 0.05) gives a value between -0.05 and +0.05
	var jitter: float = randf_range(-0.05, 0.05)
	inherited += jitter

	return inherited


# ---------------------------------------------------------------------------
# MUTATION LOGIC
# ---------------------------------------------------------------------------

## Calculates the probability of a mutation based on parent stability.
## Formula: (1.0 - average_stability) * 0.5
## Both parents stability 1.0: (1.0 - 1.0) * 0.5 = 0.0 (0% chance -- perfect stability)
## Both parents stability 0.5: (1.0 - 0.5) * 0.5 = 0.25 (25% chance)
## Both parents stability 0.2: (1.0 - 0.2) * 0.5 = 0.40 (40% chance -- very unstable)
## The 0.5 multiplier keeps mutations from being too common.
static func _calculate_mutation_chance(parent_a: Strain, parent_b: Strain) -> float:
	var avg_stability: float = (parent_a.stability + parent_b.stability) / 2.0
	var chance: float = (1.0 - avg_stability) * 0.5
	return chance


## Applies a mutation to the child strain using the NAMED EVENT system.
## This is what makes breeding exciting -- you might get a Trait Surge
## (payload jumps up!), a Degradation (resilience tanks), or if you're
## incredibly lucky, a Hypergenesis (everything goes up).
##
## The function:
## 1. Picks a mutation type using weighted random selection
## 2. Applies the mechanical effects (trait shifts) for that event type
## 3. Builds a mutation_event Dictionary on the child with name, description,
##    color, affected traits, and before/after values for the UI to display
##
## Parameters:
##   child: the strain being mutated (modified in place)
##   parent_a, parent_b: the parent strains (used for context, e.g. which
##     trait is strongest, what personalities the parents have)
static func _apply_mutation(child: Strain, parent_a: Strain, parent_b: Strain) -> void:
	# Pick which mutation event happens using weighted random selection
	var event_type: MutationType = _pick_mutation_type()

	# All trait names in an array for easy random selection
	var all_traits: Array[String] = ["stealth", "speed", "payload", "resilience", "stability"]

	# This will hold the before/after values for each affected trait
	var details: Dictionary = {}
	var affected: Array[String] = []

	# Each mutation type has its own mechanical effect.
	# We use match (Godot's switch statement) to handle each one.
	match event_type:
		MutationType.SURGE:
			# TRAIT SURGE: One random trait jumps UP by +0.15 to +0.25
			# This is a beneficial mutation -- you got lucky!
			var trait_name: String = all_traits[randi_range(0, all_traits.size() - 1)]
			var old_val: float = child.get(trait_name)
			var boost: float = randf_range(0.15, 0.25)
			child.set(trait_name, old_val + boost)
			details[trait_name] = {"old": old_val, "new": child.get(trait_name)}
			affected.append(trait_name)
			child.mutation_event = {
				"event_name": "TRAIT SURGE",
				"event_desc": "%s surged! The strain's %s jumped from %.0f%% to %.0f%%." % [
					trait_name.capitalize(), trait_name.capitalize(), old_val * 100, child.get(trait_name) * 100
				],
				"event_color": Color(0.5, 0.8, 0.4),  # Sickly green (beneficial)
				"affected_traits": affected,
				"details": details,
			}

		MutationType.DEGRADE:
			# DEGRADATION: One random trait drops by -0.15 to -0.25
			# This is a harmful mutation -- ouch. But it creates strategic
			# decisions: do you keep this degraded strain or breed it away?
			var trait_name: String = all_traits[randi_range(0, all_traits.size() - 1)]
			var old_val: float = child.get(trait_name)
			var drop: float = randf_range(0.15, 0.25)
			child.set(trait_name, old_val - drop)
			details[trait_name] = {"old": old_val, "new": child.get(trait_name)}
			affected.append(trait_name)
			child.mutation_event = {
				"event_name": "DEGRADATION",
				"event_desc": "%s degraded. The strain's %s fell from %.0f%% to %.0f%%." % [
					trait_name.capitalize(), trait_name.capitalize(), old_val * 100, child.get(trait_name) * 100
				],
				"event_color": Color(0.7, 0.3, 0.3),  # Deep crimson (harmful)
				"affected_traits": affected,
				"details": details,
			}

		MutationType.INVERSION:
			# TRAIT INVERSION: The child's strongest trait becomes its weakest,
			# or its weakest becomes strongest. Dramatic but unpredictable.
			# We find the trait with the highest value and slash it,
			# OR find the lowest and boost it. 50/50 chance either way.
			if randf() < 0.5:
				# Find the child's highest trait and crash it
				var highest_trait: String = all_traits[0]
				var highest_val: float = child.get(highest_trait)
				for t in all_traits:
					if child.get(t) > highest_val:
						highest_trait = t
						highest_val = child.get(t)
				var old_val: float = highest_val
				# Invert: new value = 1.0 - old (high becomes low)
				child.set(highest_trait, 1.0 - old_val)
				details[highest_trait] = {"old": old_val, "new": child.get(highest_trait)}
				affected.append(highest_trait)
				child.mutation_event = {
					"event_name": "INVERSION",
					"event_desc": "%s inverted! Was %.0f%%, now %.0f%%. A dramatic shift." % [
						highest_trait.capitalize(), old_val * 100, child.get(highest_trait) * 100
					],
					"event_color": Color(0.6, 0.5, 0.7),  # Bruised purple (unnatural)
					"affected_traits": affected,
					"details": details,
				}
			else:
				# Find the child's lowest trait and boost it to near-max
				var lowest_trait: String = all_traits[0]
				var lowest_val: float = child.get(lowest_trait)
				for t in all_traits:
					if child.get(t) < lowest_val:
						lowest_trait = t
						lowest_val = child.get(t)
				var old_val: float = lowest_val
				# Invert: new value = 1.0 - old (low becomes high)
				child.set(lowest_trait, 1.0 - old_val)
				details[lowest_trait] = {"old": old_val, "new": child.get(lowest_trait)}
				affected.append(lowest_trait)
				child.mutation_event = {
					"event_name": "INVERSION",
					"event_desc": "%s inverted! Was %.0f%%, now %.0f%%. A dramatic shift." % [
						lowest_trait.capitalize(), old_val * 100, child.get(lowest_trait) * 100
					],
					"event_color": Color(0.6, 0.5, 0.7),
					"affected_traits": affected,
					"details": details,
				}

		MutationType.CASCADE:
			# CASCADE: 2-3 traits all shift in the SAME direction.
			# Could be a cascade bloom (all up) or cascade failure (all down).
			# 50/50 which direction. This is exciting because it affects
			# multiple stats at once -- the strain is fundamentally different.
			var num_traits: int = randi_range(2, 3)
			var is_bloom: bool = randf() < 0.5  # 50% chance of positive cascade

			# Pick random traits to cascade (shuffle and take first N)
			var shuffled: Array[String] = all_traits.duplicate()
			shuffled.shuffle()

			var shift: float = randf_range(0.10, 0.20)  # Each trait shifts 10-20%
			if not is_bloom:
				shift = -shift  # Negative for cascade failure

			for i in range(num_traits):
				var trait_name: String = shuffled[i]
				var old_val: float = child.get(trait_name)
				child.set(trait_name, old_val + shift)
				details[trait_name] = {"old": old_val, "new": child.get(trait_name)}
				affected.append(trait_name)

			var direction: String = "bloom" if is_bloom else "failure"
			child.mutation_event = {
				"event_name": "CASCADE %s" % direction.to_upper(),
				"event_desc": "Cascade %s! %d traits shifted %s." % [
					direction, num_traits, "upward" if is_bloom else "downward"
				],
				"event_color": Color(0.8, 0.6, 0.3) if is_bloom else Color(0.6, 0.3, 0.3),
				"affected_traits": affected,
				"details": details,
			}

		MutationType.PERSONALITY_EMERGENCE:
			# PERSONALITY EMERGENCE: The child gains a random personality
			# that NEITHER parent had. This is how new lineages are born.
			# Even if both parents are "Basic" (NONE), the child can emerge
			# with a personality. This is the only mutation that affects
			# personality instead of traits (we still shift one trait for
			# mechanical impact so it's not a "wasted" mutation).
			var old_personality: int = child.personality  # Before emergence

			# Pick a random personality (1-5, skipping NONE=0)
			child.personality = randi_range(1, 5) as Strain.Personality

			# Also shift one trait slightly so there's a mechanical effect
			var trait_name: String = all_traits[randi_range(0, all_traits.size() - 1)]
			var old_val: float = child.get(trait_name)
			child.set(trait_name, old_val + randf_range(0.05, 0.10))
			details[trait_name] = {"old": old_val, "new": child.get(trait_name)}
			affected.append(trait_name)

			child.mutation_event = {
				"event_name": "PERSONALITY EMERGENCE",
				"event_desc": "A new lineage emerges! This strain developed %s personality." % child.get_personality_label(),
				"event_color": Color(0.9, 0.8, 0.3),  # Bile yellow (otherworldly)
				"affected_traits": affected,
				"details": details,
			}

		MutationType.STABILITY_COLLAPSE:
			# STABILITY COLLAPSE: Stability crashes to near 0.
			# This makes the strain a genetic wildcard -- future breeding
			# with it will have very high mutation chance (low stability =
			# high mutation chance). It's a trade: this strain's offspring
			# will be unpredictable, which could be good OR bad.
			var old_val: float = child.stability
			child.stability = randf_range(0.05, 0.15)  # Crash to 5-15%
			details["stability"] = {"old": old_val, "new": child.stability}
			affected.append("stability")
			child.mutation_event = {
				"event_name": "STABILITY COLLAPSE",
				"event_desc": "Genetic instability! Stability crashed from %.0f%% to %.0f%%. Future breeding will be volatile." % [
					old_val * 100, child.stability * 100
				],
				"event_color": Color(0.7, 0.4, 0.5),  # Bruised mauve (unstable)
				"affected_traits": affected,
				"details": details,
			}

		MutationType.HYPERGENESIS:
			# HYPERGENESIS: ALL traits shift up by +0.05 to +0.08.
			# This is the jackpot. Every single trait gets a small boost.
			# It's rare (5% of mutations) but when it happens, it's amazing.
			# The child becomes strictly better than its parents expected.
			for trait_name in all_traits:
				var old_val: float = child.get(trait_name)
				child.set(trait_name, old_val + randf_range(0.05, 0.08))
				details[trait_name] = {"old": old_val, "new": child.get(trait_name)}
				affected.append(trait_name)

			child.mutation_event = {
				"event_name": "HYPERGENESIS",
				"event_desc": "HYPERGENESIS! All traits surged simultaneously. An exceptional specimen.",
				"event_color": Color(0.9, 0.85, 0.4),  # Bright bile gold (mythic)
				"affected_traits": affected,
				"details": details,
			}

	# Note: traits are clamped to 0.0-1.0 after mutations in breed()
	# (the calling function handles clamping). We don't clamp here so
	# the "new" values in details show the raw mutation result -- the
	# clamp only affects the final stored value, not the reported change.


## Picks a mutation type using weighted random selection (roulette wheel).
## Each mutation type has a weight in MUTATION_WEIGHTS. We sum all weights,
## pick a random number in that range, and walk through the types until we
## find the one we landed on.
##
## This is the standard algorithm used in games for weighted random selection.
## It's like a roulette wheel where each type is a slice proportional to its
## weight. Bigger slices (SURGE, DEGRADE) are hit more often.
##
## Returns: a MutationType enum value
static func _pick_mutation_type() -> MutationType:
	# Step 1: Sum all the weights
	var total_weight: float = 0.0
	for type in MUTATION_WEIGHTS:
		total_weight += MUTATION_WEIGHTS[type]

	# Step 2: Pick a random number in the range [0, total_weight)
	var roll: float = randf() * total_weight

	# Step 3: Walk through each type, subtracting its weight from the roll.
	# When the roll goes below 0, we've found our type.
	for type in MUTATION_WEIGHTS:
		roll -= MUTATION_WEIGHTS[type]
		if roll <= 0.0:
			return type as MutationType

	# Fallback (should never reach here if weights are set up correctly)
	# This is a safety net -- if the loop somehow doesn't return, we
	# default to SURGE as the most common type.
	return MutationType.SURGE


# ---------------------------------------------------------------------------
# PERSONALITY INHERITANCE
# ---------------------------------------------------------------------------

## Determines the child's personality based on the parents' personalities.
## Rules:
## - If both parents have personalities, the child has 50/50 chance of
##   inheriting either one.
## - If one parent has a personality and the other is NONE, 70% chance to
##   inherit the personality, 30% chance to be NONE.
## - If both parents are NONE, 10% chance of a spontaneous personality
##   emerging (random pick from all personalities).
## - If both parents have the SAME personality, the child always inherits it
##   (reinforced trait).
static func _inherit_personality(parent_a: Strain, parent_b: Strain) -> Strain.Personality:
	# Both parents have the same personality -- it's reinforced
	if parent_a.personality == parent_b.personality and parent_a.personality != Strain.Personality.NONE:
		return parent_a.personality

	# Both parents have different personalities -- 50/50 pick
	if parent_a.personality != Strain.Personality.NONE and parent_b.personality != Strain.Personality.NONE:
		if randf() < 0.5:
			return parent_a.personality
		else:
			return parent_b.personality

	# One parent has a personality, the other is NONE -- 70% inherit, 30% NONE
	if parent_a.personality != Strain.Personality.NONE:
		if randf() < 0.7:
			return parent_a.personality
		return Strain.Personality.NONE

	if parent_b.personality != Strain.Personality.NONE:
		if randf() < 0.7:
			return parent_b.personality
		return Strain.Personality.NONE

	# Both parents are NONE -- 10% chance of spontaneous personality
	if randf() < 0.1:
		return randi_range(1, 5) as Strain.Personality

	return Strain.Personality.NONE


# ---------------------------------------------------------------------------
# UTILITY
# ---------------------------------------------------------------------------

## Returns a name prefix based on generation number.
## Gen 1: "Seed" (starting strains)
## Gen 2: "Worm" (first bred generation)
## Gen 3: "Hybrid" (second breeding)
## Gen 4+: "Mutant" (advanced breeding)
static func _get_name_prefix(generation: int) -> String:
	if generation <= 1:
		return "Seed"
	elif generation == 2:
		return "Worm"
	elif generation == 3:
		return "Hybrid"
	else:
		return "Mutant"


## Compares a child's traits against both parents and returns a list of
## traits that mutated beyond the normal inheritance range.
## This is useful for the UI to highlight mutations in the discovery moment.
## Returns a Dictionary: { "trait_name": {"old": float, "new": float} }
static func detect_mutations(child: Strain, parent_a: Strain, parent_b: Strain) -> Dictionary:
	var mutations: Dictionary = {}

	var traits: Array[String] = ["stealth", "speed", "payload", "resilience", "stability"]

	for trait_name in traits:
		var child_val: float = child.get(trait_name)
		var parent_a_val: float = parent_a.get(trait_name)
		var parent_b_val: float = parent_b.get(trait_name)

		# The expected range is min(parents) - 0.05 to max(parents) + 0.05
		# (the 0.05 accounts for normal jitter). If the child's value is
		# outside this range, it was mutated.
		var min_expected: float = min(parent_a_val, parent_b_val) - 0.05
		var max_expected: float = max(parent_a_val, parent_b_val) + 0.05

		if child_val < min_expected or child_val > max_expected:
			var expected_avg: float = (max(parent_a_val, parent_b_val) * 0.6 + min(parent_a_val, parent_b_val) * 0.4)
			mutations[trait_name] = {
				"expected": expected_avg,
				"actual": child_val
			}

	return mutations