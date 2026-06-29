# ============================================================================
# breeding.gd - The Breeding System
# ============================================================================
# This script handles the logic of combining two strains into a new one.
# It's a "static" helper class -- it doesn't hold any state, it just has
# functions you call. Think of it as a laboratory procedure: you give it
# two parent strains, it gives you back a child strain.
#
# BREEDING RULES (Phase 1 -- always succeeds, no failure yet):
# 1. Each trait of the child is a weighted average of the parents' traits,
#    biased toward the stronger parent (60% stronger, 40% weaker).
# 2. Every trait has a small random jitter (+/- 0.05) to make even identical
#    parents produce slightly different children.
# 3. Mutation chance is based on BOTH parents' stability:
#    Low stability (both parents) = high mutation chance
#    High stability (both parents) = low mutation chance
#    A mutation randomly shifts a trait by a larger amount (up or down).
# 4. The child's generation is max(parent_a.generation, parent_b.generation) + 1.
# 5. The child inherits a personality from one of the parents (random pick),
#    or if both parents have NONE, there's a small chance of a spontaneous
#    personality emerging.
# 6. Breeding costs data (currency). The cost goes up with generation.
#
# We save the risk mechanics (breeding failure, degraded offspring) for
# Phase 2. Phase 1 breeding always produces a valid child.
# ============================================================================

class_name Breeding
extends RefCounted

# ---------------------------------------------------------------------------
# BREEDING COST
# ---------------------------------------------------------------------------

## Returns the data cost to breed two strains.
## Higher generation strains are more expensive to breed.
## Formula: base_cost + max_generation * cost_per_gen
## Two gen-1 strains: 150 + 1*50 = 200 data
## Two gen-3 strains: 150 + 3*50 = 300 data
## Two gen-5 strains: 150 + 5*50 = 400 data
## (Was base 50, per_gen 10 -- tripled to make breeding a real decision.
## With income halved, you now need to save up and choose carefully.)
static func get_breed_cost(parent_a: Strain, parent_b: Strain) -> int:
	var max_gen: int = max(parent_a.generation, parent_b.generation)
	var base_cost: int = 150
	var cost_per_gen: int = 50
	return base_cost + max_gen * cost_per_gen

# ---------------------------------------------------------------------------
# MAIN BREEDING FUNCTION
# ---------------------------------------------------------------------------

## Combines two parent strains and returns a new child strain.
## Returns null if the parents are the same strain (you can't breed a strain
## with itself -- that would be cloning, not breeding).
static func breed(parent_a: Strain, parent_b: Strain) -> Strain:
	# Safety check: can't breed a strain with itself
	if parent_a == parent_b:
		push_error("Breeding: cannot breed a strain with itself!")
		return null

	# Create the child strain
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
	if randf() < mutation_chance:
		_apply_mutation(child)

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


## Applies a mutation to the child strain.
## A mutation randomly shifts 1-3 traits by a larger amount than normal jitter.
## The shift can be positive (beneficial mutation) or negative (harmful mutation).
## This is what makes breeding exciting -- you might get something amazing
## or something terrible. The discovery moment.
static func _apply_mutation(child: Strain) -> void:
	# Pick how many traits mutate (1 to 3)
	var num_mutations: int = randi_range(1, 3)

	# Put all trait names in an array so we can pick randomly
	# We store them as strings and use set() to modify the property by name
	var trait_names: Array[String] = ["stealth", "speed", "payload", "resilience", "stability"]

	# Shuffle the array so we pick random traits to mutate
	trait_names.shuffle()

	# Mutate the first N traits
	for i in range(num_mutations):
		var trait_name: String = trait_names[i]

		# Mutation magnitude: shift the trait by -0.15 to +0.15
		# This is 3x the normal jitter, enough to create meaningful change
		var mutation_amount: float = randf_range(-0.15, 0.15)

		# Get the current value, apply the mutation, and set it back
		# We use get() and set() to access properties by string name
		var current_value: float = child.get(trait_name)
		var new_value: float = current_value + mutation_amount
		child.set(trait_name, new_value)

	# Note: we don't print which traits mutated here -- the calling code
	# can detect mutations by comparing parent and child traits.
	# The discovery moment UI (Phase 2) will highlight mutations visually.


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