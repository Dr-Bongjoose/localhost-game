# ============================================================================
# strain.gd - The Strain Data Model
# ============================================================================
# This script defines what a "strain" IS in our game. A strain is a sentient
# malware organism that the player breeds, deploys, and collects.
#
# In Godot, a script like this creates a custom "class" (a blueprint for
# objects). When we say `Strain.new()`, Godot creates a new object that has
# all the properties and methods defined below.
#
# We extend "Resource" instead of "Node" because a strain is DATA, not a
# thing that exists in the game world. Resources are lightweight containers
# for data. They can be saved to disk (useful later for the codex/save
# system) and passed around between scenes easily. Nodes, by contrast,
# are objects that live in the scene tree and do things every frame.
# Think of it this way:
#   Resource = a recipe card (just information)
#   Node = a chef in the kitchen (actually does the cooking)
# A strain's stats are a recipe card. The UI that displays them is the chef.
# ============================================================================

class_name Strain
extends Resource

# ---------------------------------------------------------------------------
# CORE TRAITS - These affect gameplay directly
# ---------------------------------------------------------------------------
# Each trait is a float (decimal number) from 0.0 to 1.0.
# 0.0 = terrible at this trait, 1.0 = perfect at this trait.
# Think of them as percentages: 0.3 = 30%, 0.7 = 70%.
#
# @export_range puts a slider in Godot's inspector so you can drag to change
# the value. The "0.0, 1.0, 0.01" means: min=0.0, max=1.0, step=0.01.
# @export just makes the variable visible in the inspector at all.
#
# Why 0.0-1.0 instead of 1-100? It makes the math clean:
#   income = payload * 10  (a 0.5 payload strain earns 5 data/sec)
#   detection_chance = stealth * zone_detection_rate (simple multiplication)
# No need to divide by 100 everywhere.

@export_range(0.0, 1.0, 0.01) var stealth: float = 0.3
## How well this strain avoids detection in a zone.
## High stealth = stays hidden longer, less heat generated.

@export_range(0.0, 1.0, 0.01) var speed: float = 0.5
## How fast this strain spreads through a server.
## High speed = reaches full income potential quicker.

@export_range(0.0, 1.0, 0.01) var payload: float = 0.5
## How much data this strain extracts per cycle.
## This is the main income driver. High payload = more data per second.

@export_range(0.0, 1.0, 0.01) var resilience: float = 0.4
## How well this strain survives security countermeasures.
## High resilience = less likely to be destroyed during a raid.

@export_range(0.0, 1.0, 0.01) var stability: float = 0.7
## How stable this strain's code is during breeding.
## LOW stability = MORE mutations (can be good OR bad).
## HIGH stability = predictable offspring (safe breeding).

# ---------------------------------------------------------------------------
# PERSONALITY TRAIT - Affects behavior and heat generation
# ---------------------------------------------------------------------------
# This is an enum (enumeration) - a fixed list of named options.
# It's like a dropdown menu in the inspector. The user can only pick one of
# these predefined values, not type a random string. This prevents typos
# like "agressive" (missing an 's') breaking the game.
#
# In GDScript, enums are actually just integers under the hood.
# NONE = 0, AGGRESSIVE = 1, PARASITIC = 2, etc.
# But we use the name so the code is readable: Personality.AGGRESSIVE

enum Personality {
	NONE,        ## No personality (used for seed/basic strains)
	AGGRESSIVE,  ## Spreads faster but raises heat quicker
	PARASITIC,   ## Drains resources but weakens neighboring strains
	SYMBIOTIC,   ## Boosts adjacent strains but produces less on its own
	DORMANT,     ## Produces very little but nearly undetectable
	VOLATILE,    ## High output but random performance swings
}

@export var personality: Personality = Personality.NONE

# ---------------------------------------------------------------------------
# METADATA - Information about this strain's identity and history
# ---------------------------------------------------------------------------

@export var strain_name: String = "Unnamed Strain"
## Display name shown in UI and codex.

@export var generation: int = 1
## How many breeding cycles produced this strain.
## Generation 1 = seed strain (the one you start with).
## Generation 5 = great-great-grandchild of a seed.

@export var discovery_date: String = ""
## When this strain was first created/discovered (for codex display).
## Stored as a string like "2026-06-28" for simple display.

# ---------------------------------------------------------------------------
# CALCULATED PROPERTIES - Not stored, computed on demand
# ---------------------------------------------------------------------------
# These are "getters" - functions that calculate a value when called.
# We don't store them because they're derived from the traits above.
# If we stored them, they could go out of sync when traits change.

## Returns the data (currency) this strain generates per second.
## Formula: payload is the base, speed modifies it.
## A strain with 0.5 payload and 0.5 speed earns: 0.5 * 5 * (0.5 + 0.5) = 2.5
## A strain with 0.8 payload and 0.7 speed earns: 0.8 * 5 * (0.7 + 0.5) = 4.8
## The * 5 is a base multiplier we can tune for game balance.
## (Was * 10 -- halved to make data accumulate slower so breeding feels like
## a real investment, not something you can spam.)
func get_income_per_second() -> float:
	# Base income from payload (how much data it can extract)
	var base_income: float = payload * 5.0
	# Speed bonus: faster strains reach more of the server, extracting more
	# The (speed + 0.5) means even a slow strain gets 50% of its base income
	var speed_multiplier: float = speed + 0.5
	return base_income * speed_multiplier


## Returns how much heat (threat) this strain generates per second in a zone.
## Aggressive strains generate more heat. Stealthy strains generate less.
## Dormant strains generate almost none.
func get_heat_per_second() -> float:
	# Base heat from existing in a zone - even a stealthy strain makes some heat
	var base_heat: float = 0.5

	# Stealth reduces heat (harder to detect = less attention drawn)
	var heat_after_stealth: float = base_heat * (1.0 - stealth)

	# Personality modifies heat generation
	match personality:
		Personality.AGGRESSIVE:
			# Aggressive strains are noisy - double heat
			heat_after_stealth *= 2.0
		Personality.DORMANT:
			# Dormant strains are nearly invisible - 90% heat reduction
			heat_after_stealth *= 0.1
		Personality.VOLATILE:
			# Volatile strains are unpredictable - heat fluctuates
			# We use randf_range for the swing; average is still higher than base
			heat_after_stealth *= randf_range(0.5, 2.5)
		Personality.PARASITIC:
			# Parasitic strains are moderately noisy
			heat_after_stealth *= 1.5
		Personality.SYMBIOTIC:
			# Symbiotic strains are quiet - they cooperate, don't attack
			heat_after_stealth *= 0.7
		Personality.NONE:
			# No personality - base heat unchanged
			pass

	return heat_after_stealth


## Returns a text description of this strain's personality for UI display.
func get_personality_label() -> String:
	match personality:
		Personality.AGGRESSIVE:
			return "Aggressive"
		Personality.PARASITIC:
			return "Parasitic"
		Personality.SYMBIOTIC:
			return "Symbiotic"
		Personality.DORMANT:
			return "Dormant"
		Personality.VOLATILE:
			return "Volatile"
		Personality.NONE:
			return "Basic"
		_:
			return "Unknown"


## Returns a short text summary of all traits for debugging and tooltips.
func get_summary() -> String:
	var summary: String = "%s (Gen %d)\n" % [strain_name, generation]
	summary += "Stealth: %.0f%% | Speed: %.0f%% | Payload: %.0f%%\n" % [stealth * 100, speed * 100, payload * 100]
	summary += "Resilience: %.0f%% | Stability: %.0f%%\n" % [resilience * 100, stability * 100]
	summary += "Personality: %s\n" % get_personality_label()
	summary += "Income: %.1f data/sec | Heat: %.1f/sec" % [get_income_per_second(), get_heat_per_second()]
	return summary

# ---------------------------------------------------------------------------
# STATIC FACTORY METHOD - Creates new strains
# ---------------------------------------------------------------------------
# "static" means you call this on the class itself (Strain.create_random())
# rather than on an instance (some_strain.create_random()).
# It's like a factory that produces new strain objects.

## Creates a new strain with randomized traits.
## Used for: generating the starting seed strain, spawning wild strains.
## Parameters:
##   min_gen: minimum generation number (usually 1 for new games)
##   name_prefix: prefix for the auto-generated name (e.g. "Worm")
static func create_random(min_gen: int = 1, name_prefix: String = "Worm") -> Strain:
	# Inside a static method, we can't reference the class name "Strain"
	# directly in GDScript. We use new() which creates an instance of
	# whatever class this script is attached to (Strain in this case).
	var strain = new()

	# Generate a name like "Worm-042" using a random number
	var random_id: int = randi_range(1, 999)
	strain.strain_name = "%s-%03d" % [name_prefix, random_id]

	# Random traits - each is a random float between 0.1 and 0.9
	# We don't use full 0.0-1.0 range for random strains because extremes
	# should come from breeding and mutations, not from the starting pool.
	strain.stealth = randf_range(0.1, 0.9)
	strain.speed = randf_range(0.1, 0.9)
	strain.payload = randf_range(0.1, 0.9)
	strain.resilience = randf_range(0.1, 0.9)
	strain.stability = randf_range(0.3, 0.9)  # Stability starts higher = fewer early mutations

	# 30% chance to have a personality trait (70% chance it's "Basic"/NONE)
	# This means most early strains are simple, personalities come from breeding
	if randf() < 0.3:
		# Pick a random personality from the enum (1 to 5, skipping NONE=0)
		strain.personality = randi_range(1, 5)

	strain.generation = min_gen

	# Set today's date as discovery date
	# Time singleton gives us access to the system clock
	var date_dict: Dictionary = Time.get_date_dict_from_system()
	strain.discovery_date = "%04d-%02d-%02d" % [date_dict["year"], date_dict["month"], date_dict["day"]]

	return strain


## Creates the starting seed strain for a new game.
## This is deliberately mediocre so the player has room to improve through
## breeding. If the seed strain was great, there'd be no reason to breed.
static func create_seed() -> Strain:
	var strain = new()
	strain.strain_name = "Seed-001"
	strain.stealth = 0.4
	strain.speed = 0.5
	strain.payload = 0.3   # Low payload - you'll want to breed for better
	strain.resilience = 0.5
	strain.stability = 0.8  # High stability - safe for first breeding
	strain.personality = Personality.NONE  # Basic - no personality yet
	strain.generation = 1
	strain.discovery_date = "Origin"
	return strain