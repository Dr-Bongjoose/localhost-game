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

# Containment view nodes
@onready var containment_view: Control = $ScrollContainer/MarginContainer/VBox/ContainmentView
@onready var strain_name_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/StrainNameLabel
@onready var traits_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/TraitsLabel
@onready var data_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/DataLabel
@onready var income_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/IncomeLabel
@onready var heat_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/HeatLabel

# Breeding panel references (inside containment view)
@onready var parent_a_dropdown: OptionButton = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/ParentADropdown
@onready var parent_b_dropdown: OptionButton = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/ParentBDropdown
@onready var breed_button: Button = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedButton
@onready var breed_cost_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedCostLabel
@onready var breed_result_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/BreedPanel/BreedResultLabel

# Strain collection references (inside containment view)
@onready var strain_list_label: Label = $ScrollContainer/MarginContainer/VBox/ContainmentView/StrainListLabel
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

const BREED_COOLDOWN_TIME: float = 5.0

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
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

	# Update all UI
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

	update_breed_cost_display()
	_switch_view("containment")


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

	var result_text: String = "NEW STRAIN DISCOVERED!\n"
	result_text += "%s (Generation %d)\n" % [child.strain_name, child.generation]
	result_text += "Codex Entry: %s\n" % rarity_name

	if mutations.is_empty():
		result_text += "No mutations detected."
	else:
		result_text += "MUTATIONS DETECTED:\n"
		for trait_name in mutations:
			var data: Dictionary = mutations[trait_name]
			result_text += "  %s: expected %.0f%%, got %.0f%%\n" % [
				trait_name.capitalize(),
				data["expected"] * 100,
				data["actual"] * 100
			]

	breed_result_label.text = result_text

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
## collection and shows a notification.
func _handle_raids(raids: Array) -> void:
	for raid in raids:
		var strain: Strain = raid["strain"]
		var survived: bool = raid["survived"]
		if survived:
			zone_action_label.text = "RAID! %s survived!" % strain.strain_name
			print("RAID: %s survived in %s" % [strain.strain_name, zones[active_zone_index].zone_name])
		else:
			# Strain was destroyed! Remove from player's collection.
			zone_action_label.text = "RAID! %s was DESTROYED!" % strain.strain_name
			print("RAID: %s destroyed in %s" % [strain.strain_name, zones[active_zone_index].zone_name])

			# Remove from the zone (already done in zone.tick(), but clean up our map)
			strain_deploy_map.erase(strain.strain_name)

			# Remove from player's collection
			var idx: int = player_strains.find(strain)
			if idx != -1:
				player_strains.remove_at(idx)
				# Adjust active strain index if needed
				if active_strain_index >= player_strains.size():
					active_strain_index = max(0, player_strains.size() - 1)

			# Refresh all UI
			update_strain_display()
			update_strain_list()
			update_breeding_dropdowns()
			update_deploy_dropdown()
			update_breed_cost_display()


# ---------------------------------------------------------------------------
# INPUT HANDLING
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
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