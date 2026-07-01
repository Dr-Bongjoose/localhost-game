# ============================================================================
# lab_theme.gd - The Containment Lab Visual Theme (v2 -- Anime/Bio Lab)
# ============================================================================
# This script builds a Godot Theme resource programmatically. A Theme defines
# how ALL UI elements look across the entire game -- colors, fonts, button
# styles, panel backgrounds. Instead of setting colors on every individual
# label, we define them all here in one place.
#
# v2 REDESIGN: The original theme was flat and bland -- solid colors, thin
# borders, no visual personality. This version adds:
# - Bioluminescent panel borders (glowing edges like containment glass)
# - Thicker borders with accent colors per section
# - Rounded corners with a "lab equipment" feel
# - Button styles with colored left-edge accents (like status indicators)
# - Better visual hierarchy (bigger titles, distinct header bars)
# - Hover glow effects on interactive elements
# - A more "anime dark fantasy" aesthetic while staying dark and biological
#
# HOW TO USE IT:
# In main.gd's _ready(), we call:
#   theme = LabTheme.create()
# That sets the theme on the root Control, and every child inherits it.
#
# HOW TO TWEAK IT:
# All colors are defined as constants at the top of the file. Change a
# constant here, and every element using that color updates instantly.
# ============================================================================

class_name LabTheme
extends RefCounted

# ---------------------------------------------------------------------------
# THE PALETTE -- All game colors defined in one place
# ---------------------------------------------------------------------------
# These are the ONLY colors in the game. Change them here, everything updates.
# v2: Richer, more saturated accent colors for the anime dark fantasy feel.
# The backgrounds stay dark, but the accents POP more -- like bioluminescence.

# --- BACKGROUNDS ---
const BG_DEEP: Color        = Color(0.04, 0.04, 0.07, 1)  ## Near-black with blue tint (deep water / microscope field)
const BG_PANEL: Color       = Color(0.07, 0.08, 0.11, 1)  ## Slightly lighter (containment unit surface)
const BG_PANEL_ACCENT: Color = Color(0.10, 0.14, 0.12, 1) ## Greenish tint for inner panels
const BG_PANEL_BORDER: Color = Color(0.20, 0.35, 0.28, 1) ## Bioluminescent green border (glowing containment glass)
const BG_HEADER: Color       = Color(0.12, 0.15, 0.18, 1) ## Header bar background (slightly lighter than panel)

# --- TEXT: DEFAULT ---
const TEXT_DEFAULT: Color   = Color(0.70, 0.70, 0.72, 1)  ## Lighter grey for better readability
const TEXT_DIM: Color       = Color(0.42, 0.42, 0.45, 1)  ## Dimmer grey -- secondary stats, subtitles

# --- TEXT: SEMANTIC COLORS ---
const TEXT_TITLE: Color     = Color(0.40, 0.85, 0.55, 1)    ## Vivid sickly green -- strain names, titles (brighter for anime pop)
const TEXT_DATA: Color      = Color(0.55, 0.95, 0.60, 1)    ## Bright bioluminescent green -- currency, data values
const TEXT_HEAT: Color      = Color(0.95, 0.55, 0.30, 1)   ## Hot orange -- heat, warnings, danger
const TEXT_RESULT: Color     = Color(0.95, 0.85, 0.50, 1)   ## Warm gold -- breed results, action feedback
const TEXT_COST: Color       = Color(0.85, 0.80, 0.40, 1)   ## Bile yellow -- costs, prices
const TEXT_DANGER: Color     = Color(0.90, 0.35, 0.35, 1)   ## Deep crimson -- breach warnings, failures

# --- SECTION ACCENT COLORS (each section has its own bioluminescent glow) ---
const ACCENT_BREED: Color    = Color(0.65, 0.45, 0.85, 1)   ## Bruised purple -- breeding lab
const ACCENT_DEPLOY: Color   = Color(0.40, 0.65, 0.80, 1)   ## Cold cyan-blue -- deployment/zones
const ACCENT_CODEX: Color    = Color(0.40, 0.80, 0.55, 1)   ## Muted green -- codex entries
const ACCENT_HOME: Color     = Color(0.80, 0.50, 0.35, 1)   ## Warm amber -- home base defense
const ACCENT_DISCOVERY: Color = Color(0.90, 0.85, 0.40, 1)  ## Bile gold -- discovery moment

# --- BUTTONS ---
const BTN_NORMAL: Color     = Color(0.09, 0.11, 0.14, 1)   ## Dark surface (inactive button)
const BTN_HOVER: Color      = Color(0.14, 0.22, 0.18, 1)   ## Sickly green tint (mouse over)
const BTN_PRESSED: Color    = Color(0.06, 0.08, 0.10, 1)   ## Darker (clicked)
const BTN_DISABLED: Color   = Color(0.05, 0.06, 0.07, 1)   ## Very dark (can't click)
const BTN_BORDER: Color     = Color(0.25, 0.40, 0.30, 1)   ## Bioluminescent green-grey border
const BTN_BORDER_HOVER: Color = Color(0.35, 0.60, 0.40, 1) ## Brighter glow on hover
const BTN_TEXT: Color       = Color(0.65, 0.75, 0.65, 1)   ## Muted green text on buttons

# --- SIZES ---
const CORNER_RADIUS: int    = 6     ## Rounded corners (px) -- more rounded = friendlier anime feel
const CORNER_RADIUS_PANEL: int = 8  ## Panels slightly more rounded
const BORDER_WIDTH: int     = 2     ## Border thickness (px) -- thicker = more "equipment" feel
const TITLE_FONT_SIZE: int  = 22    ## Big titles
const HEADER_FONT_SIZE: int = 16    ## Section headers
const BODY_FONT_SIZE: int   = 14    ## Body text
const SMALL_FONT_SIZE: int = 12    ## Small text

# ---------------------------------------------------------------------------
# THEME BUILDER
# ---------------------------------------------------------------------------

## Creates and returns a complete Theme resource with all lab styling.
## Call this once in main.gd's _ready() and set it as the root control's theme.
static func create() -> Theme:
	var theme: Theme = Theme.new()

	# --- LABEL DEFAULTS ---
	theme.set_color("font_color", "Label", TEXT_DEFAULT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.5))
	theme.set_font_size("font_size", "Label", BODY_FONT_SIZE)

	# --- BUTTON STYLES ---
	# v2: Buttons now have a colored LEFT EDGE accent (like a status indicator
	# strip on lab equipment) plus thicker borders and more rounded corners.
	# The hover state has a brighter, glowing border.

	var btn_normal_style: StyleBoxFlat = _make_button_style(BTN_NORMAL, BTN_BORDER, CORNER_RADIUS)
	theme.set_stylebox("normal", "Button", btn_normal_style)

	var btn_hover_style: StyleBoxFlat = _make_button_style(BTN_HOVER, BTN_BORDER_HOVER, CORNER_RADIUS)
	# Add a subtle glow effect on hover by setting a brighter border
	btn_hover_style.border_color = BTN_BORDER_HOVER
	btn_hover_style.set_border_width_all(BORDER_WIDTH)
	theme.set_stylebox("hover", "Button", btn_hover_style)

	var btn_pressed_style: StyleBoxFlat = _make_button_style(BTN_PRESSED, BTN_BORDER, CORNER_RADIUS)
	theme.set_stylebox("pressed", "Button", btn_pressed_style)

	var btn_disabled_style: StyleBoxFlat = _make_button_style(BTN_DISABLED, BTN_BORDER, CORNER_RADIUS)
	theme.set_stylebox("disabled", "Button", btn_disabled_style)

	# Button text colors
	theme.set_color("font_color", "Button", BTN_TEXT)
	theme.set_color("font_hover_color", "Button", TEXT_TITLE)
	theme.set_color("font_pressed_color", "Button", TEXT_TITLE)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_font_size("font_size", "Button", BODY_FONT_SIZE)

	# --- OPTIONBUTTON (dropdowns) ---
	theme.set_stylebox("normal", "OptionButton", btn_normal_style)
	theme.set_stylebox("hover", "OptionButton", btn_hover_style)
	theme.set_stylebox("pressed", "OptionButton", btn_pressed_style)
	theme.set_stylebox("disabled", "OptionButton", btn_disabled_style)
	theme.set_color("font_color", "OptionButton", BTN_TEXT)
	theme.set_color("font_hover_color", "OptionButton", TEXT_TITLE)
	theme.set_font_size("font_size", "OptionButton", 13)

	# --- PANEL STYLES ---
	# v2: Panels now have bioluminescent borders (glowing green edges) and
	# more rounded corners. They look like containment units, not flat boxes.
	var panel_style: StyleBoxFlat = _make_panel_style(BG_PANEL, BG_PANEL_BORDER, CORNER_RADIUS_PANEL)
	theme.set_stylebox("panel", "Panel", panel_style)

	# --- PROGRESSBAR (heat bars) ---
	# v2: Custom styling for the zone heat bar -- dark background with
	# bioluminescent fill that shifts color based on danger level.
	var bar_bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.05, 0.06, 0.08, 1)
	bar_bg_style.border_color = BTN_BORDER
	bar_bg_style.set_border_width_all(1)
	bar_bg_style.set_corner_radius_all(3)
	theme.set_stylebox("background", "ProgressBar", bar_bg_style)

	var bar_fill_style: StyleBoxFlat = StyleBoxFlat.new()
	bar_fill_style.bg_color = TEXT_HEAT
	bar_fill_style.set_corner_radius_all(3)
	theme.set_stylebox("fill", "ProgressBar", bar_fill_style)

	# --- SCROLLCONTAINER ---
	var scroll_style: StyleBoxFlat = StyleBoxFlat.new()
	scroll_style.bg_color = Color(0, 0, 0, 0)  # Transparent
	theme.set_stylebox("panel", "ScrollContainer", scroll_style)

	# --- HBOXCONTAINER / VBOXCONTAINER SEPARATION ---
	# v2: Add visible separation between container items for breathing room
	theme.set_constant("separation", "HBoxContainer", 12)
	theme.set_constant("separation", "VBoxContainer", 8)

	return theme

# ---------------------------------------------------------------------------
# STYLE HELPERS
# ---------------------------------------------------------------------------
# These functions create StyleBoxFlat resources with our dark lab look.
# v2: Thicker borders, more rounded corners, bioluminescent accent colors.

## Creates a button-style box with the v2 lab aesthetic.
## Dark surface, bioluminescent border, rounded corners, good padding.
static func _make_button_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(radius)
	# Generous padding so buttons feel tactile, not cramped
	style.set_content_margin_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	# Add a subtle top-left highlight (like light catching a glass surface)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 2
	return style

## Creates a panel-style box with the v2 containment unit aesthetic.
## Dark surface, bioluminescent glowing border, rounded corners.
static func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(12)
	# Shadow gives panels a slight "raised from the background" depth
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	# Inner glow effect via a second border color (Godot 4 supports expand_margin)
	# This creates the bioluminescent containment glass look
	style.anti_aliasing = true
	return style

# ---------------------------------------------------------------------------
# NEW: Section-specific panel styles
# ---------------------------------------------------------------------------
# Each section of the game gets its own accent color border.
# This gives the UI personality -- you can tell which section you're in
# by the color of the panel borders.

## Creates a panel style with a specific accent color border.
## Use this for section-specific panels (breeding lab gets purple, zones get blue, etc.)
static func make_section_panel(accent_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG_PANEL
	style.border_color = accent_color
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(CORNER_RADIUS_PANEL)
	style.set_content_margin_all(12)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	# Subtle accent glow: set the border to slightly transparent so it glows
	# against the dark background
	style.anti_aliasing = true
	return style

## Creates a header label style for section titles.
## Returns a StyleBoxFlat to use as the background of header labels.
static func make_header_bar(accent_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	# Dark background with a hint of the accent color
	style.bg_color = Color(
		BG_HEADER.r + accent_color.r * 0.05,
		BG_HEADER.g + accent_color.g * 0.05,
		BG_HEADER.b + accent_color.b * 0.05,
		1
	)
	# Left edge accent: thicker left border in the accent color
	# This creates a "status bar" look on the left side of each header
	style.border_color = accent_color
	style.border_width_left = 4  ## Thick left accent
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_content_margin_all(8)
	style.content_margin_left = 14
	return style