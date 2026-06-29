# ============================================================================
# lab_theme.gd - The Containment Lab Visual Theme
# ============================================================================
# This script builds a Godot Theme resource programmatically. A Theme defines
# how ALL UI elements look across the entire game -- colors, fonts, button
# styles, panel backgrounds. Instead of setting colors on every individual
# label (which we were doing with 14+ theme_override_colors in main.tscn),
# we define them all here in one place.
#
# THINK OF IT LIKE CSS:
#   Instead of style="color: green" on every <p> tag,
#   you write p { color: green; } once in a stylesheet.
#   This file is the stylesheet.
#
# HOW TO USE IT:
# In main.gd's _ready(), we call:
#   theme = LabTheme.create()
# That sets the theme on the root Control, and every child inherits it.
# Labels get the default text color. Buttons get the dark lab style.
# Panels get the containment-unit look.
#
# HOW TO TWEAK IT:
# All colors are defined as constants at the top of this file. Change a
# constant here, and every element using that color updates instantly.
# You don't need to hunt through main.tscn anymore.
#
# THE PALETTE (from VISUAL_DESIGN.md):
# The aesthetic is "dark biological unsettling" -- not cyberpunk, not neon.
# Colors that feel slightly wrong -- alive but shouldn't be.
#   - Deep dark backgrounds (near black, like deep water or microscope field)
#   - Muted biological colors: sickly greens, bruised purples, bile yellows
#   - Deep crimson reds for danger
#   - Ashen grey for mundane text
# ============================================================================

class_name LabTheme
extends RefCounted

# ---------------------------------------------------------------------------
# THE PALETTE -- All game colors defined in one place
# ---------------------------------------------------------------------------
# These are the ONLY colors in the game. Change them here, everything updates.
# The names describe the FEELING, not just the hue ("bile_yellow" not "yellow").

# --- BACKGROUNDS ---
const BG_DEEP: Color        = Color(0.05, 0.05, 0.08, 1)  ## Near-black with blue tint (deep water / microscope field)
const BG_PANEL: Color       = Color(0.08, 0.09, 0.12, 1)  ## Slightly lighter (containment unit surface)
const BG_PANEL_BORDER: Color = Color(0.15, 0.18, 0.20, 1) ## Thin border on panels (like glass edge)

# --- TEXT: DEFAULT ---
const TEXT_DEFAULT: Color   = Color(0.65, 0.65, 0.65, 1)  ## Ashen grey -- body text, lists, labels
const TEXT_DIM: Color       = Color(0.45, 0.45, 0.45, 1)  ## Dimmer grey -- secondary stats, subtitles

# --- TEXT: SEMANTIC COLORS (what the text MEANS, not just how it looks) ---
const TEXT_TITLE: Color     = Color(0.4, 0.7, 0.5, 1)     ## Sickly green -- strain names, titles
const TEXT_DATA: Color      = Color(0.6, 0.85, 0.6, 1)    ## Brighter green -- currency, data values
const TEXT_HEAT: Color      = Color(0.8, 0.5, 0.3, 1)     ## Orange-red -- heat, warnings, danger
const TEXT_RESULT: Color    = Color(0.9, 0.8, 0.5, 1)     ## Warm yellow -- breed results, action feedback
const TEXT_COST: Color      = Color(0.8, 0.8, 0.4, 1)     ## Bile yellow -- costs, prices

# --- SECTION HEADERS (each view has a slightly different accent) ---
const HEADER_BREED: Color   = Color(0.7, 0.5, 0.8, 1)     ## Bruised purple -- breeding lab
const HEADER_DEPLOY: Color  = Color(0.5, 0.6, 0.7, 1)     ## Cold blue-purple -- deployment
const HEADER_CODEX: Color   = Color(0.5, 0.7, 0.6, 1)     ## Muted green -- codex entries

# --- BUTTONS ---
const BTN_NORMAL: Color     = Color(0.10, 0.12, 0.14, 1)  ## Dark surface (inactive button)
const BTN_HOVER: Color      = Color(0.15, 0.22, 0.18, 1)  ## Sickly green tint (mouse over)
const BTN_PRESSED: Color    = Color(0.08, 0.10, 0.12, 1)  ## Darker (clicked)
const BTN_DISABLED: Color   = Color(0.06, 0.07, 0.08, 1) ## Very dark (can't click)
const BTN_BORDER: Color     = Color(0.2, 0.25, 0.22, 1)   ## Subtle green-grey border
const BTN_TEXT: Color       = Color(0.6, 0.7, 0.6, 1)     ## Muted green text on buttons

# ---------------------------------------------------------------------------
# THEME BUILDER
# ---------------------------------------------------------------------------

## Creates and returns a complete Theme resource with all lab styling.
## Call this once in main.gd's _ready() and set it as the root control's theme.
static func create() -> Theme:
	var theme: Theme = Theme.new()

	# --- LABEL DEFAULTS ---
	# Every Label in the game gets these by default. Individual labels can
	# still override with theme_override_colors if they need a special color
	# (like the data counter using TEXT_DATA green).
	theme.set_color("font_color", "Label", TEXT_DEFAULT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	# Default font size for Labels (individual labels can still override)
	theme.set_font_size("font_size", "Label", 14)

	# --- BUTTON STYLES ---
	# A StyleBoxFlat is a solid-color box with optional borders and rounded corners.
	# We create one for each button state (normal, hover, pressed, disabled).
	# This is what makes buttons look like dark lab controls instead of default Godot buttons.

	# Normal state (not interacting)
	var btn_normal_style: StyleBoxFlat = _make_button_style(BTN_NORMAL, BTN_BORDER)
	theme.set_stylebox("normal", "Button", btn_normal_style)

	# Hover state (mouse over) -- slight green tint
	var btn_hover_style: StyleBoxFlat = _make_button_style(BTN_HOVER, BTN_BORDER)
	theme.set_stylebox("hover", "Button", btn_hover_style)

	# Pressed state (clicking) -- darker
	var btn_pressed_style: StyleBoxFlat = _make_button_style(BTN_PRESSED, BTN_BORDER)
	theme.set_stylebox("pressed", "Button", btn_pressed_style)

	# Disabled state (can't click)
	var btn_disabled_style: StyleBoxFlat = _make_button_style(BTN_DISABLED, BTN_BORDER)
	theme.set_stylebox("disabled", "Button", btn_disabled_style)

	# Button text color
	theme.set_color("font_color", "Button", BTN_TEXT)
	theme.set_color("font_hover_color", "Button", TEXT_TITLE)
	theme.set_color("font_pressed_color", "Button", TEXT_TITLE)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_font_size("font_size", "Button", 14)

	# --- OPTIONBUTTON (dropdowns) ---
	# OptionButtons use the same Button styles but also have a dropdown arrow.
	# We give them the same dark lab look.
	theme.set_stylebox("normal", "OptionButton", btn_normal_style)
	theme.set_stylebox("hover", "OptionButton", btn_hover_style)
	theme.set_stylebox("pressed", "OptionButton", btn_pressed_style)
	theme.set_stylebox("disabled", "OptionButton", btn_disabled_style)
	theme.set_color("font_color", "OptionButton", BTN_TEXT)
	theme.set_color("font_hover_color", "OptionButton", TEXT_TITLE)
	theme.set_font_size("font_size", "OptionButton", 13)

	# --- PANEL STYLES ---
	# Panels are the dark translucent surfaces that contain grouped controls
	# (the breeding lab panel, the deployment panel). They should look like
	# containment unit glass -- dark, slightly bordered, slightly recessed.
	var panel_style: StyleBoxFlat = _make_panel_style(BG_PANEL, BG_PANEL_BORDER)
	theme.set_stylebox("panel", "Panel", panel_style)

	# --- SCROLLCONTAINER ---
	# Make the scroll container background transparent (the Background ColorRect
	# behind it shows through with the deep dark color).
	var scroll_style: StyleBoxFlat = StyleBoxFlat.new()
	scroll_style.bg_color = Color(0, 0, 0, 0)  # Transparent
	theme.set_stylebox("panel", "ScrollContainer", scroll_style)

	return theme

# ---------------------------------------------------------------------------
# STYLE HELPERS
# ---------------------------------------------------------------------------
# These functions create StyleBoxFlat resources with our dark lab look.
# StyleBoxFlat is Godot's "solid color box with borders and corners" style.

## Creates a button-style box: dark surface with subtle border and slight rounding.
static func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)        # Slightly rounded corners (3px)
	# Internal padding so text isn't flush against the edges
	style.set_content_margin_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

## Creates a panel-style box: darker surface, thin border, more padding.
static func _make_panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)        # Slightly more rounded than buttons
	style.set_content_margin_all(10)
	return style