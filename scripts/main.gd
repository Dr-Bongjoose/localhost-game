# ============================================================================
# main.gd - The Game Manager
# ============================================================================
# This script controls the main game scene. It manages:
# - The player's collection of strains (list of owned strains)
# - Passive income from all strains (idle + zone income)
# - The breeding interface (select two parents, breed, get a child)
# - The codex (permanent record of every strain ever discovered)
# - The zone system (deploy strains to zones for bonus income + raid risk)
# - Heat management (rises from strains, decays over time)
# - Tab switching between Containment, Codex, and Zones views
#
# The game has three views:
#   CONTAINMENT -- where you see your active strains, breed, and manage
#   CODEX -- where you browse every strain you've ever discovered
#   ZONES -- where you deploy strains to zones for bonus income
# ============================================================================

extends Control

# ---------------------------------------------------------------------------
# UI REFERENCES
# ---------------------------------------------------------------------------

# Tab buttons (switch between views)
@onready var tab_containment: Button = $ScrollContainer/MarginContainer/VBox/TabBar/TabContainment
@onready var tab_codex: Button = $ScrollContainer/MarginContainer/VBox/TabBar/TabCodex
@onready var tab_zones: Button = $ScrollContainer/MarginContainer/VBox/TabBar/TabZones

# New Game button (deletes save and restarts fresh)
@onready var new_game_button: Button = $ScrollContainer/MarginContainer/VBox/HeaderBar/NewGameButton

# Containment view nodes
@onready var containment_view: Control = $ScrollContainer/MarginContainer/VBox/ContainmentView
@onready var strain_name_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/StrainNameLabel
@onready var traits_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/TraitsLabel

# Status bar (always visible, outside the views)
@onready var data_label: Label = $ScrollContainer/MarginContainer/VBox/StatusBar/StatusHBox/DataLabel
@onready var income_label: Label = $ScrollContainer/MarginContainer/VBox/StatusBar/StatusHBox/IncomeLabel
@onready var heat_label: Label = $ScrollContainer/MarginContainer/VBox/StatusBar/StatusHBox/HeatLabel

# Breeding panel references (inside containment view)
@onready var parent_a_dropdown: OptionButton = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/ParentADropdown
@onready var parent_b_dropdown: OptionButton = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/ParentBDropdown
@onready var breed_button: Button = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedButton
@onready var breed_cost_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedCostLabel
@onready var breed_result_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedResultLabel

# Strain collection references (inside containment view)
@onready var strain_list_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/StrainListPanel/StrainListLabel
@onready var prev_button: Button = $ScrollContainer/MarginContainer/VBox/ContainmentView/NavButtons/PrevButton
@onready var next_button: Button = $ScrollContainer/MarginContainer/VBox/ContainmentView/NavButtons/NextButton

# Codex view nodes
@onready var codex_view: Control = $ScrollContainer/MarginContainer/VBox/CodexView
@onready var codex_summary_label: Label = $ScrollContainer/MarginContainer/VBox/CodexView/CodexSummaryLabel
@onready var codex_entry_label: Label = $ScrollContainer/MarginContainer/VBox/CodexView/CodexEntryLabel
@onready var codex_prev_button: Button = $ScrollContainer/MarginContainer/VBox/CodexView/CodexNav/CodexPrevButton
@onready var codex_next_button: Button = $ScrollContainer/MarginContainer/VBox/CodexView/CodexNav/CodexNextButton
@onready var codex_counter_label: Label = $ScrollContainer/MarginContainer/VBox/CodexView/CodexNav/CodexCounterLabel

# Zones view nodes
@onready var zones_view: Control = $ScrollContainer/MarginContainer/VBox/ZonesView
@onready var zone_info_label: Label = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneInfoLabel
@onready var zone_nav_prev: Button = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneNav/ZonePrevButton
@onready var zone_nav_next: Button = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneNav/ZoneNextButton
@onready var zone_counter_label: Label = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneNav/ZoneCounterLabel
@onready var zone_deploy_dropdown: OptionButton = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/DeployDropdown
@onready var zone_deploy_button: Button = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/DeployButton
@onready var zone_recall_button: Button = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/RecallButton
@onready var zone_action_label: Label = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/ZoneActionLabel

# Zone heat bar (visual danger indicator)
@onready var zone_heat_bar: ProgressBar = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneHeatBar

# Raid alert overlay (flashes on screen when a raid happens)
@onready var raid_alert_overlay: Panel = $RaidAlertOverlay
@onready var raid_alert_text: Label = $RaidAlertOverlay/RaidAlertText
@onready var raid_alert_bg: ColorRect = $RaidAlertOverlay/RaidAlertBG

# Discovery moment overlay (the "new strain bred" reveal)
@onready var discovery_overlay: Panel = $DiscoveryOverlay
@onready var discovery_title: Label = $DiscoveryOverlay/DiscoveryTitle
@onready var discovery_name: Label = $DiscoveryOverlay/DiscoveryName
@onready var discovery_rarity: Label = $DiscoveryOverlay/DiscoveryRarity
@onready var discovery_traits: Label = $DiscoveryOverlay/DiscoveryTraits
@onready var discovery_mutations: Label = $DiscoveryOverlay/DiscoveryMutations
@onready var discovery_hint: Label = $DiscoveryOverlay/DiscoveryHint
@onready var discovery_bg: ColorRect = $DiscoveryOverlay/DiscoveryBG

# ---------------------------------------------------------------------------
# GAME STATE
# ---------------------------------------------------------------------------

var player_strains: Array[Strain] = []  ## All strains the player currently owns
var active_strain_index: int = 0       ## Which strain is currently displayed (containment)
var player_data: float = 0.0           ## Currency (data) accumulated
var total_heat: float = 0.0            ## Current global threat level
var breed_cooldown: float = 0.0        ## Seconds before next breed allowed

var codex: Codex = null                 ## The strain codex (bestiary)
var codex_index: int = 0               ## Which codex entry is displayed

var zones: Array[Zone] = []             ## All available zones
var active_zone_index: int = 0         ## Which zone is displayed (zones view)

var current_view: String = "containment"  ## "containment", "codex", or "zones"

## Tracks which zone each strain is deployed to (strain -> Zone, or null if idle)
## We use the strain's name as key since Strain is a Resource (not hashable by default)
var strain_deploy_map: Dictionary = {}

const BREED_COOLDOWN_TIME: float = 15.0  ## Was 5s -- increased so each breed is a deliberate choice

# --- SAVE SYSTEM ---
# Auto-save fires every AUTO_SAVE_INTERVAL seconds so a crash or accidental
# close doesn't wipe your progress. We also save once on exit.
const AUTO_SAVE_INTERVAL: float = 30.0  ## How often to auto-save (seconds)
var _auto_save_timer: float = 0.0       ## Counts up toward next auto-save

# --- RAID ALERT ---
# When a raid happens, we show a full-screen overlay that flashes red.
# This timer counts down how long the overlay stays visible before auto-hiding.
var _raid_alert_timer: float = 0.0      ## Time remaining on the raid alert overlay
const RAID_ALERT_DURATION: float = 3.0  ## How long the raid alert stays on screen (seconds)

# --- DISCOVERY MOMENT ---
# When breeding produces a new strain, we show a dramatic reveal overlay.
# Each element fades in sequentially (title, then name, then rarity, then traits).
# The player taps the screen to dismiss it, or it auto-dismisses after a timeout.
var _discovery_active: bool = false    ## Is the discovery overlay currently showing?

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	# --- APPLY THE LAB THEME ---
	# The theme defines all colors, button styles, and panel styles for the
	# entire game. Setting it on the root Control means every child inherits it.
	# Individual labels can still override with theme_override_colors for special
	# cases (like the data counter using a brighter green).
	theme = LabTheme.create()

	# --- APPLY SEMANTIC COLORS TO SPECIFIC LABELS ---
	# The theme sets a default text color, but certain labels need special colors
	# based on what they MEAN (data, heat, titles, section headers).
	# We set these here so the colors live in code (version-controlled) rather
	# than scattered in the .tscn file.
	#
	# Each label gets a theme_override_color. This overrides the theme's default
	# for that specific label only.
	_apply_label_colors()

	# --- TRY TO LOAD SAVE ---
	# Before creating a new game, check if a save file exists.
	# If it does, load it. If not (or if loading fails), start fresh.
	if SaveSystem.has_save():
		if _load_game():
			print("Save loaded successfully -- continuing saved game")
		else:
			print("Save file exists but failed to load -- starting new game")
			_init_new_game()
	else:
		print("No save file found -- starting new game")
		_init_new_game()

	# Update all UI (works for both loaded and new game)
	update_strain_display()
	update_strain_list()
	update_breeding_dropdowns()
	update_codex_display()
	update_zone_display()
	update_deploy_dropdown()

	# Connect button signals
	breed_button.pressed.connect(_on_breed_button_pressed)
	prev_button.pressed.connect(_on_prev_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)
	tab_containment.pressed.connect(_on_tab_containment_pressed)
	tab_codex.pressed.connect(_on_tab_codex_pressed)
	tab_zones.pressed.connect(_on_tab_zones_pressed)
	codex_prev_button.pressed.connect(_on_codex_prev_pressed)
	codex_next_button.pressed.connect(_on_codex_next_pressed)
	zone_nav_prev.pressed.connect(_on_zone_prev_pressed)
	zone_nav_next.pressed.connect(_on_zone_next_pressed)
	zone_deploy_button.pressed.connect(_on_deploy_pressed)
	zone_recall_button.pressed.connect(_on_recall_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)

	update_breed_cost_display()
	_switch_view("containment")


## Initializes a brand new game with starting strains and zones.
## Called from _ready() when no save file exists (or save is corrupted).
## This is the old _ready() logic, split out so _ready() can try loading first.
func _init_new_game() -> void:
	codex = Codex.new()

	# Create the 4 zone types (all unlocked in Phase 1)
	zones.append(Zone.create(Zone.ZoneType.CONSUMER))
	zones.append(Zone.create(Zone.ZoneType.CORPORATE))
	zones.append(Zone.create(Zone.ZoneType.GOVERNMENT))
	zones.append(Zone.create(Zone.ZoneType.DARK_WEB))

	# Start with two seed strains
	player_strains.append(Strain.create_seed())
	player_strains.append(Strain.create_random(1, "Worm"))
	codex.add_strain(player_strains[0])
	codex.add_strain(player_strains[1])


## Deletes the save file and resets all game state to a fresh new game.
## Called when the player clicks the "New Game" button.
## This is essential during development for testing the new player experience
## without manually hunting down the save file on disk.
func _on_new_game_pressed() -> void:
	# Delete the save file
	SaveSystem.delete_save()

	# Reset all game state to empty
	player_strains.clear()
	zones.clear()
	strain_deploy_map.clear()
	player_data = 0.0
	total_heat = 0.0
	breed_cooldown = 0.0
	active_strain_index = 0
	codex_index = 0
	active_zone_index = 0
	_auto_save_timer = 0.0
	_raid_alert_timer = 0.0

	# Hide any active overlays
	raid_alert_overlay.visible = false
	_discovery_active = false
	discovery_overlay.visible = false
	discovery_overlay.modulate.a = 1.0

	# Re-enable breed button if it was cooling
	breed_button.disabled = false
	breed_button.text = "Breed Strains"

	# Initialize a fresh new game
	_init_new_game()

	# Update all UI
	update_strain_display()
	update_strain_list()
	update_breeding_dropdowns()
	update_codex_display()
	update_zone_display()
	update_deploy_dropdown()
	update_breed_cost_display()
	_switch_view("containment")

	print("New game started -- save deleted and state reset")


## Applies semantic colors to specific labels throughout the UI.
## This replaces the 14+ theme_override_colors that were scattered in main.tscn.
## Now all colors are defined in lab_theme.gd as named constants, and we just
## reference them here. Change a color in lab_theme.gd, everything updates.
##
## WHY SOME LABELS USE add_theme_color_override AND OTHERS DON'T:
#  Labels that should use the default text color (TEXT_DEFAULT ashen grey)
#  don't need any override -- they get it from the theme automatically.
#  Only labels with a SPECIAL meaning get an override:
#  - Strain names -> sickly green (titles)
#  - Data counter -> bright green (currency)
#  - Heat -> orange-red (warning)
#  - Section headers -> purple/blue/green accents
#  - Results/costs -> yellow tones
func _apply_label_colors() -> void:
	# --- CONTAINMENT VIEW ---

	# Strain name = title (sickly green)
	strain_name_label.add_theme_color_override("font_color", LabTheme.TEXT_TITLE)

	# Data counter = currency (bright green)
	data_label.add_theme_color_override("font_color", LabTheme.TEXT_DATA)

	# Income = secondary stat (dim grey -- comes from theme default, no override needed)

	# Heat = warning (orange-red)
	heat_label.add_theme_color_override("font_color", LabTheme.TEXT_HEAT)

	# Strain list = default grey (no override needed, uses theme default)

	# --- BREEDING PANEL ---

	# Section header = bruised purple
	var breed_title: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedTitle
	breed_title.add_theme_color_override("font_color", LabTheme.HEADER_BREED)

	# Cost = bile yellow
	var breed_cost: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedCostLabel
	breed_cost.add_theme_color_override("font_color", LabTheme.TEXT_COST)

	# Result = warm yellow (action feedback)
	var breed_result: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedResultLabel
	breed_result.add_theme_color_override("font_color", LabTheme.TEXT_RESULT)

	# --- CODEX VIEW ---

	# Summary = default grey (no override needed)

	# Entry display = muted green (codex entries have a clinical green tint)
	var codex_entry: Label = $ScrollContainer/MarginContainer/VBox/CodexView/CodexEntryLabel
	codex_entry.add_theme_color_override("font_color", LabTheme.HEADER_CODEX)

	# --- ZONES VIEW ---

	# Zone info = muted green
	var zone_info: Label = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneInfoLabel
	zone_info.add_theme_color_override("font_color", LabTheme.HEADER_CODEX)

	# Section header = cold blue-purple
	var deploy_title: Label = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/DeployTitle
	deploy_title.add_theme_color_override("font_color", LabTheme.HEADER_DEPLOY)

	# Action label = warm yellow (action feedback, same as breed result)
	var zone_action: Label = $ScrollContainer/MarginContainer/VBox/ZonesView/ZoneDeployPanel/ZoneActionLabel
	zone_action.add_theme_color_override("font_color", LabTheme.TEXT_RESULT)


# ---------------------------------------------------------------------------
# MAIN LOOP
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# --- IDLE INCOME ---
	# Strains not deployed to a zone still earn their base income (idle).
	# Strains deployed to a zone earn base income * zone.data_value instead.
	# So we calculate idle income (non-deployed strains) + zone income separately.
	var idle_income: float = 0.0
	for strain in player_strains:
		if not _is_strain_deployed(strain):
			idle_income += strain.get_income_per_second()

	# --- ZONE INCOME + TICKING ---
	var zone_income: float = 0.0
	var raid_notifications: Array = []
	for zone in zones:
		zone_income += zone.get_zone_income()
		# Tick the zone (handles heat + raid checks)
		var result: Dictionary = zone.tick(delta)
		if result["raids"].size() > 0:
			for raid in result["raids"]:
				raid_notifications.append(raid)

	# Total player income = idle + zone
	player_data += (idle_income + zone_income) * delta

	# --- GLOBAL HEAT ---
	# Global heat comes from all strains (idle + deployed)
	# This is separate from per-zone heat (which triggers raids)
	var total_heat_gen: float = 0.0
	for strain in player_strains:
		total_heat_gen += strain.get_heat_per_second()
	total_heat += total_heat_gen * delta
	total_heat *= 1.0 - (0.01 * delta)

	# --- BREED COOLDOWN ---
	if breed_cooldown > 0.0:
		breed_cooldown -= delta
		if breed_cooldown <= 0.0:
			breed_cooldown = 0.0
			breed_button.disabled = false
			breed_button.text = "Breed Strains"

	# --- RAID NOTIFICATIONS ---
	if not raid_notifications.is_empty():
		_handle_raids(raid_notifications)

	# --- UI UPDATE ---
	update_data_display()
	if current_view == "zones":
		update_zone_display()

	# --- AUTO-SAVE ---
	# Count up toward the next auto-save. When the timer hits the interval,
	# save the game and reset the timer. This ensures a crash or accidental
	# close never loses more than 30 seconds of progress.
	_auto_save_timer += delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		_save_game()

	# --- RAID ALERT FADE ---
	# If the raid alert overlay is visible, count down the timer and hide it
	# when it reaches zero. This auto-dismisses the alert after RAID_ALERT_DURATION
	# seconds so the player doesn't have to click anything.
	if _raid_alert_timer > 0.0:
		_raid_alert_timer -= delta
		if _raid_alert_timer <= 0.0:
			_raid_alert_timer = 0.0
			raid_alert_overlay.visible = false


# ---------------------------------------------------------------------------
# VIEW SWITCHING
# ---------------------------------------------------------------------------

func _switch_view(view_name: String) -> void:
	current_view = view_name
	containment_view.visible = (view_name == "containment")
	codex_view.visible = (view_name == "codex")
	zones_view.visible = (view_name == "zones")

	tab_containment.disabled = (view_name == "containment")
	tab_codex.disabled = (view_name == "codex")
	tab_zones.disabled = (view_name == "zones")


func _on_tab_containment_pressed() -> void:
	_switch_view("containment")


func _on_tab_codex_pressed() -> void:
	_switch_view("codex")
	update_codex_display()


func _on_tab_zones_pressed() -> void:
	_switch_view("zones")
	update_zone_display()
	update_deploy_dropdown()


# ---------------------------------------------------------------------------
# CONTAINMENT VIEW UI
# ---------------------------------------------------------------------------

func update_strain_display() -> void:
	if player_strains.is_empty():
		strain_name_label.text = "No strains"
		traits_label.text = ""
		return
	var strain: Strain = player_strains[active_strain_index]
	strain_name_label.text = strain.strain_name
	# Add deployment status to the summary
	var summary: String = strain.get_summary()
	var dep_zone: Zone = _get_strain_zone(strain)
	if dep_zone != null:
		summary += "\n[Deployed: %s]" % dep_zone.zone_name
	else:
		summary += "\n[Idle]"
	traits_label.text = summary


func update_data_display() -> void:
	data_label.text = "Data: %.0f" % floor(player_data)

	# Calculate total income (idle + zone)
	var idle_income: float = 0.0
	for strain in player_strains:
		if not _is_strain_deployed(strain):
			idle_income += strain.get_income_per_second()
	var z_income: float = 0.0
	for zone in zones:
		z_income += zone.get_zone_income()

	var total_income: float = idle_income + z_income
	income_label.text = "Income: %.1f/sec (%d strains)" % [total_income, player_strains.size()]
	heat_label.text = "Heat: %.1f" % total_heat


func update_strain_list() -> void:
	var list_text: String = "Strains (%d):\n" % player_strains.size()
	for i in range(player_strains.size()):
		var strain: Strain = player_strains[i]
		var marker: String = "  "
		if i == active_strain_index:
			marker = "> "
		# Show deployment status in the list
		var dep_zone: Zone = _get_strain_zone(strain)
		var dep_tag: String = ""
		if dep_zone != null:
			dep_tag = " [%s]" % dep_zone.get_type_name()
		list_text += "%s%s (Gen %d)%s\n" % [marker, strain.strain_name, strain.generation, dep_tag]
	strain_list_label.text = list_text


func update_breeding_dropdowns() -> void:
	parent_a_dropdown.clear()
	parent_b_dropdown.clear()
	for i in range(player_strains.size()):
		var strain: Strain = player_strains[i]
		var label: String = "%s (Gen %d)" % [strain.strain_name, strain.generation]
		parent_a_dropdown.add_item(label, i)
		parent_b_dropdown.add_item(label, i)
	parent_a_dropdown.select(0)
	if player_strains.size() > 1:
		parent_b_dropdown.select(1)
	else:
		parent_b_dropdown.select(0)


func update_breed_cost_display() -> void:
	if player_strains.size() < 2:
		breed_cost_label.text = "Need at least 2 strains to breed"
		breed_button.disabled = true
		return
	var idx_a: int = parent_a_dropdown.get_selected_id()
	var idx_b: int = parent_b_dropdown.get_selected_id()
	var strain_a: Strain = player_strains[idx_a]
	var strain_b: Strain = player_strains[idx_b]
	var cost: int = Breeding.get_breed_cost(strain_a, strain_b)
	if idx_a == idx_b:
		breed_cost_label.text = "Select two DIFFERENT strains"
		breed_button.disabled = true
	elif player_data < cost:
		breed_cost_label.text = "Cost: %d data (not enough!)" % cost
		breed_button.disabled = true
	else:
		breed_cost_label.text = "Cost: %d data" % cost
		breed_button.disabled = false


# ---------------------------------------------------------------------------
# BREEDING
# ---------------------------------------------------------------------------

func _on_breed_button_pressed() -> void:
	var idx_a: int = parent_a_dropdown.get_selected_id()
	var idx_b: int = parent_b_dropdown.get_selected_id()

	if idx_a == idx_b:
		breed_result_label.text = "Cannot breed a strain with itself!"
		return
	if player_strains.size() < 2:
		breed_result_label.text = "Need at least 2 strains!"
		return

	var parent_a: Strain = player_strains[idx_a]
	var parent_b: Strain = player_strains[idx_b]
	var cost: int = Breeding.get_breed_cost(parent_a, parent_b)
	if player_data < cost:
		breed_result_label.text = "Not enough data! Need %d." % cost
		return

	player_data -= cost
	var child: Strain = Breeding.breed(parent_a, parent_b)
	if child == null:
		breed_result_label.text = "Breeding failed (error)!"
		player_data += cost
		return

	player_strains.append(child)
	var codex_idx: int = codex.add_strain(child)
	codex.increment_breed_count(parent_a)
	codex.increment_breed_count(parent_b)
	active_strain_index = player_strains.size() - 1

	var mutations: Dictionary = Breeding.detect_mutations(child, parent_a, parent_b)
	var rarity: Codex.Rarity = codex.calculate_rarity(child)
	var rarity_name: String = codex.get_rarity_name(rarity)

	# Keep a short summary in the breed result label too (for when the overlay closes)
	var result_text: String = "Bred: %s (Gen %d) [%s]" % [child.strain_name, child.generation, rarity_name]
	if not mutations.is_empty():
		result_text += " -- %d mutation(s)!" % mutations.size()
	breed_result_label.text = result_text

	# --- SHOW THE DISCOVERY MOMENT ---
	# Instead of just dumping text, we show a dramatic reveal overlay.
	# Each element fades in sequentially using Tweens (Godot's animation tool).
	_show_discovery_moment(child, rarity, mutations)

	breed_cooldown = BREED_COOLDOWN_TIME
	breed_button.disabled = true
	breed_button.text = "Cooling (%.0fs)" % breed_cooldown

	update_strain_display()
	update_strain_list()
	update_breeding_dropdowns()
	update_codex_display()

	parent_a_dropdown.select(min(idx_a, player_strains.size() - 2))
	parent_b_dropdown.select(min(idx_b, player_strains.size() - 1))
	update_breed_cost_display()

	print("Bred %s + %s = %s [%s] (cost: %d, mutations: %d)" % [
		parent_a.strain_name, parent_b.strain_name, child.strain_name,
		rarity_name, cost, mutations.size()
	])


# ---------------------------------------------------------------------------
# STRAIN NAVIGATION
# ---------------------------------------------------------------------------

func _on_prev_button_pressed() -> void:
	if player_strains.is_empty():
		return
	active_strain_index -= 1
	if active_strain_index < 0:
		active_strain_index = player_strains.size() - 1
	update_strain_display()
	update_strain_list()


func _on_next_button_pressed() -> void:
	if player_strains.is_empty():
		return
	active_strain_index += 1
	if active_strain_index >= player_strains.size():
		active_strain_index = 0
	update_strain_display()
	update_strain_list()


# ---------------------------------------------------------------------------
# CODEX VIEW
# ---------------------------------------------------------------------------

func update_codex_display() -> void:
	codex_summary_label.text = codex.get_summary()
	if codex.get_count() == 0:
		codex_entry_label.text = "No strains discovered yet.\nBreed strains to fill your codex!"
		codex_counter_label.text = "0 / 0"
		return
	codex_index = clampi(codex_index, 0, codex.get_count() - 1)
	codex_entry_label.text = codex.get_entry_details(codex_index)
	codex_counter_label.text = "%d / %d" % [codex_index + 1, codex.get_count()]


func _on_codex_prev_pressed() -> void:
	if codex.get_count() == 0:
		return
	codex_index -= 1
	if codex_index < 0:
		codex_index = codex.get_count() - 1
	update_codex_display()


func _on_codex_next_pressed() -> void:
	if codex.get_count() == 0:
		return
	codex_index += 1
	if codex_index >= codex.get_count():
		codex_index = 0
	update_codex_display()


# ---------------------------------------------------------------------------
# ZONES VIEW
# ---------------------------------------------------------------------------

func update_zone_display() -> void:
	if zones.is_empty():
		zone_info_label.text = "No zones available"
		zone_counter_label.text = "0 / 0"
		return

	active_zone_index = clampi(active_zone_index, 0, zones.size() - 1)
	var zone: Zone = zones[active_zone_index]
	zone_info_label.text = zone.get_summary()
	zone_counter_label.text = "%d / %d" % [active_zone_index + 1, zones.size()]

	# --- ZONE HEAT BAR ---
	# Show the zone's current heat as a progress bar from 0 to the zone's
	# detection threshold. The bar fills up as heat rises, and the color
	# changes from green (safe) to yellow (caution) to red (danger).
	var heat_pct: float = zone.zone_heat / zone.detection_threshold
	zone_heat_bar.max_value = zone.detection_threshold
	zone_heat_bar.value = zone.zone_heat

	# Color the heat bar based on danger level:
	# < 50% of threshold = muted green (safe)
	# 50-75% = bile yellow (caution, should think about recalling)
	# > 75% = deep crimson (danger, raid imminent)
	var heat_color: Color
	if heat_pct < 0.5:
		heat_color = Color(0.3, 0.5, 0.3)      # Muted green
	elif heat_pct < 0.75:
		heat_color = Color(0.7, 0.65, 0.25)    # Bile yellow
	else:
		heat_color = Color(0.7, 0.2, 0.15)     # Deep crimson

	# Apply the color to the progress bar's fill (the "fill" stylebox)
	# We use a StyleBoxFlat so we can control the fill color directly
	var heat_fill: StyleBoxFlat = StyleBoxFlat.new()
	heat_fill.bg_color = heat_color
	heat_fill.set_corner_radius_all(2)
	zone_heat_bar.add_theme_stylebox_override("fill", heat_fill)

	# Update deploy button state
	var selected_strain: Strain = _get_selected_deploy_strain()
	if selected_strain == null:
		zone_deploy_button.disabled = true
		zone_recall_button.disabled = true
		zone_action_label.text = "No strains available to deploy"
	elif zone.has_strain(selected_strain):
		zone_deploy_button.disabled = true
		zone_recall_button.disabled = false
		zone_action_label.text = "%s is deployed here" % selected_strain.strain_name
	elif _is_strain_deployed(selected_strain):
		zone_deploy_button.disabled = true
		zone_recall_button.disabled = true
		zone_action_label.text = "%s is deployed elsewhere. Recall it first." % selected_strain.strain_name
	elif zone.is_full():
		zone_deploy_button.disabled = true
		zone_recall_button.disabled = true
		zone_action_label.text = "Zone is full (%d/%d)" % [zone.deployed_strains.size(), zone.capacity]
	else:
		zone_deploy_button.disabled = false
		zone_recall_button.disabled = true
		zone_action_label.text = "Ready to deploy %s" % selected_strain.strain_name


func update_deploy_dropdown() -> void:
	zone_deploy_dropdown.clear()
	for i in range(player_strains.size()):
		var strain: Strain = player_strains[i]
		var label: String = "%s (Gen %d)" % [strain.strain_name, strain.generation]
		var dep_zone: Zone = _get_strain_zone(strain)
		if dep_zone != null:
			label += " [%s]" % dep_zone.get_type_name()
		zone_deploy_dropdown.add_item(label, i)
	if player_strains.size() > 0:
		zone_deploy_dropdown.select(0)


func _get_selected_deploy_strain() -> Strain:
	if player_strains.is_empty():
		return null
	var idx: int = zone_deploy_dropdown.get_selected_id()
	if idx < 0 or idx >= player_strains.size():
		return null
	return player_strains[idx]


func _on_deploy_pressed() -> void:
	var strain: Strain = _get_selected_deploy_strain()
	if strain == null:
		return
	var zone: Zone = zones[active_zone_index]
	if zone.deploy(strain):
		strain_deploy_map[strain.strain_name] = zone
		zone_action_label.text = "Deployed %s to %s!" % [strain.strain_name, zone.zone_name]
		update_strain_display()
		update_strain_list()
		update_deploy_dropdown()
	else:
		zone_action_label.text = "Failed to deploy (zone full?)"


func _on_recall_pressed() -> void:
	var strain: Strain = _get_selected_deploy_strain()
	if strain == null:
		return
	var zone: Zone = zones[active_zone_index]
	if zone.recall(strain):
		strain_deploy_map.erase(strain.strain_name)
		zone_action_label.text = "Recalled %s from %s" % [strain.strain_name, zone.zone_name]
		update_strain_display()
		update_strain_list()
		update_deploy_dropdown()
	else:
		zone_action_label.text = "That strain isn't in this zone"


func _on_zone_prev_pressed() -> void:
	if zones.is_empty():
		return
	active_zone_index -= 1
	if active_zone_index < 0:
		active_zone_index = zones.size() - 1
	update_zone_display()


func _on_zone_next_pressed() -> void:
	if zones.is_empty():
		return
	active_zone_index += 1
	if active_zone_index >= zones.size():
		active_zone_index = 0
	update_zone_display()


# ---------------------------------------------------------------------------
# ZONE HELPERS
# ---------------------------------------------------------------------------

## Checks if a strain is deployed to any zone.
func _is_strain_deployed(strain: Strain) -> bool:
	return strain_deploy_map.has(strain.strain_name)


## Returns the Zone a strain is deployed to, or null if idle.
func _get_strain_zone(strain: Strain) -> Zone:
	if strain_deploy_map.has(strain.strain_name):
		return strain_deploy_map[strain.strain_name]
	return null


## Handles raid results -- removes destroyed strains from the player's
## collection and shows a flashing alert overlay on screen.
## This replaces the old behavior of quietly replacing text in a label.
func _handle_raids(raids: Array) -> void:
	# Build the alert message from all raid results
	var alert_lines: Array = []
	for raid in raids:
		var strain: Strain = raid["strain"]
		var survived: bool = raid["survived"]
		var zone: Zone = _get_strain_zone(strain)
		var zone_name: String = "Unknown Zone"
		if zone != null:
			zone_name = zone.zone_name

		if survived:
			alert_lines.append("RAID in %s!\n%s SURVIVED" % [zone_name, strain.strain_name])
			print("RAID: %s survived in %s" % [strain.strain_name, zone_name])
		else:
			alert_lines.append("RAID in %s!\n%s was DESTROYED!" % [zone_name, strain.strain_name])
			print("RAID: %s destroyed in %s" % [strain.strain_name, zone_name])

			# Remove from the zone (already done in zone.tick(), but clean up our map)
			strain_deploy_map.erase(strain.strain_name)

			# Remove from player's collection
			var idx: int = player_strains.find(strain)
			if idx != -1:
				player_strains.remove_at(idx)
				# Adjust active strain index if needed
				if active_strain_index >= player_strains.size():
					active_strain_index = max(0, player_strains.size() - 1)

	# --- SHOW THE ALERT OVERLAY ---
	# Join all raid lines into one message and show the overlay
	var alert_msg: String = "\n\n".join(alert_lines)
	_show_raid_alert(alert_msg, !raids[0]["survived"])

	# Refresh all UI (strains may have been removed)
	update_strain_display()
	update_strain_list()
	update_breeding_dropdowns()
	update_deploy_dropdown()
	update_breed_cost_display()
	if current_view == "zones":
		update_zone_display()


## Shows the raid alert overlay with the given message.
## If a strain was destroyed, the overlay flashes more intensely (brighter red).
## The overlay auto-hides after RAID_ALERT_DURATION seconds (handled in _process).
func _show_raid_alert(message: String, strain_destroyed: bool) -> void:
	raid_alert_text.text = message
	# Brighter red if a strain was destroyed, dimmer if it survived
	if strain_destroyed:
		raid_alert_bg.color = Color(0.6, 0.05, 0.05, 0.7)
		raid_alert_text.add_theme_color_override("font_color", Color(0.95, 0.3, 0.2, 1))
	else:
		raid_alert_bg.color = Color(0.4, 0.15, 0.05, 0.5)
		raid_alert_text.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))

	raid_alert_overlay.visible = true
	_raid_alert_timer = RAID_ALERT_DURATION


# ---------------------------------------------------------------------------
# DISCOVERY MOMENT
# ---------------------------------------------------------------------------
# When breeding succeeds, this function shows a dramatic reveal overlay.
# Each element (title, name, rarity, traits, mutations) fades in sequentially
# using Godot's Tween system. A Tween is an animation tool that interpolates
# a property (like modulate alpha) from one value to another over time.
#
# The sequence:
#   0.0s: Dark overlay fades in (0.3s)
#   0.3s: "NEW STRAIN DISCOVERED" title fades in (0.4s)
#   0.7s: Strain name fades in (0.5s)
#   1.2s: Rarity tier fades in with biological color (0.4s)
#   1.6s: Traits fade in one by one (0.3s each)
#   ~3.0s: Mutations fade in (if any) (0.4s)
#   3.5s: "tap to continue" hint fades in (0.5s)
# Player taps screen to dismiss, or it stays until tapped.

## Shows the discovery moment overlay with animated sequential reveals.
func _show_discovery_moment(child: Strain, rarity: Codex.Rarity, mutations: Dictionary) -> void:
	# --- SET UP THE CONTENT ---
	discovery_name.text = "%s (Generation %d)" % [child.strain_name, child.generation]

	# Rarity with biological color
	var rarity_name: String = codex.get_rarity_name(rarity)
	var rarity_color: Color = codex.get_rarity_color(rarity)
	discovery_rarity.text = rarity_name
	discovery_rarity.add_theme_color_override("font_color", rarity_color)

	# Traits summary
	var traits_text: String = "Stealth: %.0f%% | Speed: %.0f%% | Payload: %.0f%%\n" % [
		child.stealth * 100, child.speed * 100, child.payload * 100
	]
	traits_text += "Resilience: %.0f%% | Stability: %.0f%%\n" % [
		child.resilience * 100, child.stability * 100
	]
	traits_text += "Personality: %s" % child.get_personality_label()
	discovery_traits.text = traits_text

	# Mutations (if any)
	if mutations.is_empty():
		discovery_mutations.text = "No mutations detected."
	else:
		var mut_text: String = "MUTATIONS DETECTED:\n"
		for trait_name in mutations:
			var data: Dictionary = mutations[trait_name]
			mut_text += "  %s: expected %.0f%%, got %.0f%%\n" % [
				trait_name.capitalize(),
				data["expected"] * 100,
				data["actual"] * 100
			]
		discovery_mutations.text = mut_text

	# --- RESET ALL ELEMENTS TO INVISIBLE ---
	# modulate.a = 0 means fully transparent. We fade them in with tweens.
	discovery_title.modulate.a = 0.0
	discovery_name.modulate.a = 0.0
	discovery_rarity.modulate.a = 0.0
	discovery_traits.modulate.a = 0.0
	discovery_mutations.modulate.a = 0.0
	discovery_hint.modulate.a = 0.0
	discovery_bg.modulate.a = 0.0

	# Show the overlay
	discovery_overlay.visible = true
	_discovery_active = true

	# --- ANIMATE THE SEQUENCE ---
	# create_tween() makes a new Tween attached to this node. It auto-frees
	# when the animation completes. We chain sequential animations using
	# tween_property() + set the delay so each element appears after the previous.

	var tween: Tween = create_tween()

	# 1. Dark background fades in (0 to 1 alpha over 0.3s)
	tween.tween_property(discovery_bg, "modulate:a", 1.0, 0.3)

	# 2. Title fades in (0.3s delay, 0.4s duration)
	tween.tween_property(discovery_title, "modulate:a", 1.0, 0.4).set_delay(0.0)

	# 3. Strain name fades in (after title, 0.5s duration)
	tween.tween_property(discovery_name, "modulate:a", 1.0, 0.5)

	# 4. Rarity fades in (after name, 0.4s duration)
	tween.tween_property(discovery_rarity, "modulate:a", 1.0, 0.4)

	# 5. Traits fade in (after rarity, 0.5s duration)
	tween.tween_property(discovery_traits, "modulate:a", 1.0, 0.5)

	# 6. Mutations fade in (after traits, 0.4s duration)
	tween.tween_property(discovery_mutations, "modulate:a", 1.0, 0.4)

	# 7. "tap to continue" hint fades in last (0.5s duration)
	tween.tween_property(discovery_hint, "modulate:a", 1.0, 0.5)

	# When the tween completes, the hint is fully visible and the player can tap.
	# The overlay stays visible until tapped (handled in _unhandled_input).


## Hides the discovery moment overlay and resets state.
## Called when the player taps the screen during the discovery moment.
func _hide_discovery_moment() -> void:
	if not _discovery_active:
		return

	# Fade out the whole overlay over 0.3s, then hide it
	var tween: Tween = create_tween()
	tween.tween_property(discovery_overlay, "modulate:a", 0.0, 0.3)
	# When the fade-out completes, hide the overlay and reset alpha for next time
	tween.tween_callback(func():
		discovery_overlay.visible = false
		discovery_overlay.modulate.a = 1.0
		_discovery_active = false
	)


# ---------------------------------------------------------------------------
# INPUT HANDLING
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# --- DISCOVERY MOMENT: TAP TO DISMISS ---
	# If the discovery overlay is showing, any tap or key press dismisses it.
	# We check this FIRST so the input doesn't also trigger navigation.
	if _discovery_active:
		if event is InputEventKey and event.pressed:
			_hide_discovery_moment()
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventScreenTouch and event.pressed:
			_hide_discovery_moment()
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseButton and event.pressed:
			_hide_discovery_moment()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				match current_view:
					"containment": _on_prev_button_pressed()
					"codex": _on_codex_prev_pressed()
					"zones": _on_zone_prev_pressed()
			KEY_RIGHT:
				match current_view:
					"containment": _on_next_button_pressed()
					"codex": _on_codex_next_pressed()
					"zones": _on_zone_next_pressed()
			KEY_TAB:
				# Tab key cycles through views
				match current_view:
					"containment": _on_tab_codex_pressed()
					"codex": _on_tab_zones_pressed()
					"zones": _on_tab_containment_pressed()


# ---------------------------------------------------------------------------
# SAVE / LOAD
# ---------------------------------------------------------------------------
# These functions bridge main.gd's game state and SaveSystem.
# _save_game() gathers all state into a dictionary and hands it to SaveSystem.
# _load_game() takes a dictionary from SaveSystem and rebuilds all state.
# _notification() catches the app-close event to save before exiting.

## Saves the current game state to disk.
## Called automatically every AUTO_SAVE_INTERVAL seconds and on app exit.
func _save_game() -> void:
	var state: Dictionary = SaveSystem.build_save_state(
		player_strains,
		player_data,
		total_heat,
		breed_cooldown,
		active_strain_index,
		codex,
		codex_index,
		zones,
		active_zone_index,
		strain_deploy_map
	)
	SaveSystem.save_game(state)


## Loads the game state from disk and rebuilds all game objects.
## Returns true if successful, false if the save is missing or corrupted.
## Called from _ready() on game start.
func _load_game() -> bool:
	var state: Dictionary = SaveSystem.load_game()
	if state.is_empty():
		return false

	# --- RESTORE SIMPLE VALUES ---
	player_data = state.get("player_data", 0.0)
	total_heat = state.get("total_heat", 0.0)
	breed_cooldown = state.get("breed_cooldown", 0.0)
	active_strain_index = state.get("active_strain_index", 0)
	codex_index = state.get("codex_index", 0)
	active_zone_index = state.get("active_zone_index", 0)

	# --- RESTORE STRAINS ---
	# Deserialize the player's strain collection from saved dictionaries
	var saved_strains: Array = state.get("player_strains", [])
	player_strains = SaveSystem.deserialize_strain_array(saved_strains)

	# --- RESTORE CODEX ---
	var saved_codex: Dictionary = state.get("codex", {})
	if not saved_codex.is_empty():
		codex = SaveSystem.deserialize_codex(saved_codex)
	else:
		# Fallback: rebuild codex from player strains (shouldn't happen)
		codex = Codex.new()
		for strain in player_strains:
			codex.add_strain(strain)

	# --- RESTORE ZONES ---
	# Deserialize zones (properties only, no deployed strains yet)
	var saved_zones: Array = state.get("zones", [])
	zones.clear()
	for zone_data in saved_zones:
		zones.append(SaveSystem.deserialize_zone(zone_data))

	# --- RECONNECT DEPLOYED STRAINS ---
	# Zones saved the NAMES of deployed strains. Now we find the actual
	# Strain objects in player_strains by name and put them back in the zones.
	# This also rebuilds strain_deploy_map (strain_name -> Zone).
	var saved_zone_data: Array = state.get("zones", [])
	strain_deploy_map = SaveSystem.reconnect_deployed_strains(zones, player_strains, saved_zone_data)

	# --- VALIDATION ---
	# If we have no strains (corrupted save), start fresh
	if player_strains.is_empty():
		print("Save loaded but has no strains -- starting new game")
		_init_new_game()
		return false

	# Clamp indices to valid ranges (in case save has stale values)
	active_strain_index = clampi(active_strain_index, 0, max(0, player_strains.size() - 1))
	codex_index = clampi(codex_index, 0, max(0, codex.get_count() - 1))
	active_zone_index = clampi(active_zone_index, 0, max(0, zones.size() - 1))

	return true


## Called by Godot when system-level events happen (app closing, focus change).
## We use it to save the game before the app exits so progress isn't lost.
func _notification(what: int) -> void:
	# WM_CLOSE_REQUEST is sent when the user closes the game window.
	# MainTree.NOTIFICATION_WM_CLOSE_REQUEST = 4, but we use the constant.
	if what == Node.NOTIFICATION_WM_CLOSE_REQUEST:
		print("App closing -- saving game...")
		_save_game()