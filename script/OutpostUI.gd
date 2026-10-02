extends Control
## Attach to your main scene's root Control node.
##
## IMPORTANT — this script now reads nodes by %UniqueName instead of
## $DeepPath. For each node below, select it in the scene tree and enable
## "Access as Unique Name" (right-click the node -> Access as Unique Name).
## Unique names survive the node being moved to a different parent; a
## $Path does not. Every required node is also asserted non-null in
## _ready(), so a missing/renamed node fails LOUDLY with the exact node
## name at startup instead of a silent null-instance crash the first time
## it's touched. See SETUP.md for the full node tree.

@onready var life_support_bar: TextureProgressBar = %LifeSupportBar
@onready var power_bar: TextureProgressBar = %PowerBar
@onready var radiation_bar: TextureProgressBar = %RadiationBar
@onready var food_bar: TextureProgressBar = %FoodBar

@onready var life_support_bar_label: Label = %LifeSupportBarLabel
@onready var power_bar_label: Label = %PowerBarLabel
@onready var radiation_bar_label: Label = %RadiationBarLabel
@onready var food_bar_label: Label = %FoodBarLabel

@onready var day_label: Label = %DayLabel
@onready var consequences_label: Label = %ConsequencesLabel
@onready var mission_log_label: Label = %MissionLogLabel
@onready var note_label: Label = %NoteLabel
@onready var resources_label: Label = %ResourcesLabel

@onready var repair_life_support_button: TextureButton = %RepairLifeSupportButton
@onready var boost_power_button: TextureButton = %BoostPowerButton
@onready var reinforce_shield_button: TextureButton = %ReinforceShieldButton
@onready var tend_food_button: TextureButton = %TendFoodButton
@onready var end_day_button: TextureButton = %EndDayButton

@onready var debrief_panel: PanelContainer = %DebriefPanel
@onready var debrief_label: Label = %DebriefLabel
@onready var restart_button: Button = %RestartButton

# Optional — not in the original node tree. Add a Label named "ForecastLabel"
# and/or a Button named "EmergencyButton" anywhere under VBoxContainer, mark
# each "Access as Unique Name", and this script will wire them up
# automatically with no further code changes. Leave them out and the
# features just stay silent/disabled.
var forecast_label: Label = null
var emergency_button: Button = null

# Optional — "Ask Kasei" chat assistant. Add a ChatButton (top-right icon)
# and a ChatPanel with the child nodes listed in _wire_optional_nodes()
# below to enable it; see README for the exact node layout. Skipped
# gracefully, like the two above, if any required chat node is missing.
var chat_button: TextureButton = null
var chat_panel: Control = null
var chat_questions_container: VBoxContainer = null
var chat_response_label: Label = null
var chat_close_button: Button = null
var assistant_engine := AssistantEngine.new()

# Optional — sol-by-sol history chart. Add a ChartButton (icon, same idea
# as ChatButton), a ChartPanel, and a ChartCanvas (a Control with
# HistoryChart.gd attached) to enable it; see README for the node layout.
var chart_button: TextureButton = null
var chart_panel: Control = null
var chart_canvas: HistoryChart = null
var chart_close_button: Button = null

# One line per vital on the chart, all drawn in the single palette color
# #724060, distinguished by line style instead of color or opacity.
const CHART_SERIES_STYLES := {
	"life_support": {"color": Color("#724060"), "style": "solid"},
	"power": {"color": Color("#724060"), "style": "dashed"},
	"radiation_shield": {"color": Color("#724060"), "style": "dotted"},
	"food_production": {"color": Color("#724060"), "style": "dash_dot"},
}

# Optional — Info popup showing each action's Energy/Manpower cost. Static
# content (pulled from StatsManager.ACTION_COSTS), no live state needed.
var info_button: TextureButton = null
var info_panel: Control = null
var info_content_label: Label = null
var info_close_button: Button = null

# Optional — one-level "undo last action" button. Enabled/disabled live
# via StatsManager.undo_availability_changed.
var undo_button: TextureButton = null

# Flavor readouts shown in the telemetry panel that aren't separately
# tracked stats — each is deliberately derived from one of the four real
# vitals so nothing on screen is fabricated independent of game state.
# Tune these ranges freely; the mapping (which vital drives which readout)
# is the part that matters for honesty, not the exact numbers.
const INTERIOR_TEMP_MIN := 6.0
const INTERIOR_TEMP_MAX := 21.0
const OXYGEN_PCT_MIN := 80.0
const OXYGEN_PCT_MAX := 100.0
const CO2_PPM_MIN := 400.0
const CO2_PPM_MAX := 1000.0
const MAX_FOOD_RESERVE_DAYS := 14
const SOLAR_INPUT_REFERENCE_HOURS := 24.0

func _derived_interior_temp() -> float:
	return lerpf(INTERIOR_TEMP_MIN, INTERIOR_TEMP_MAX, StatsManager.stats.life_support / 100.0)

func _derived_oxygen_pct() -> float:
	return lerpf(OXYGEN_PCT_MIN, OXYGEN_PCT_MAX, StatsManager.stats.life_support / 100.0)

func _derived_co2_ppm() -> float:
	return lerpf(CO2_PPM_MIN, CO2_PPM_MAX, 1.0 - StatsManager.stats.life_support / 100.0)

func _derived_water_pct() -> float:
	return StatsManager.stats.food_production

func _derived_food_reserve_days() -> int:
	return int(round(StatsManager.stats.food_production / 100.0 * MAX_FOOD_RESERVE_DAYS))

func _derived_solar_input_pct(sunlight_hours: float) -> float:
	return clampf(sunlight_hours / SOLAR_INPUT_REFERENCE_HOURS * 100.0, 0.0, 100.0)

const ACTION_TOOLTIPS := {
	"life_support": "Repair Life Support (1 Energy, 2 Crew)",
	"power": "Boost Power (0 Energy, 2 Crew)",
	"radiation_shield": "Reinforce Shield (2 Energy, 1 Crew)",
	"food_production": "Tend Food (1 Energy, 1 Crew)",
}

# Display order for the consequences breakdown, matching the
# "SOL X CONSEQUENCES" format: Power, Food Production, Shield, Life Support.
# ConsequencesLabel is hidden in the telemetry-panel layout (see
# _on_day_consequences) but this stays in case you want to re-surface it
# as a popup/toast later.
const CONSEQUENCE_ROWS := [
	{"key": "power", "label": "Power"},
	{"key": "food_production", "label": "Food Production"},
	{"key": "radiation_shield", "label": "Shield"},
	{"key": "life_support", "label": "Life Support"},
]

# Cached so the alerts block (NoteLabel) can show all three at once,
# updated independently by three different signals.
var latest_cause_text: String = ""
var latest_note_text: String = ""
var latest_forecast_text: String = ""

func _ready() -> void:
	_assert_required_nodes()
	_wire_optional_nodes()

	StatsManager.stats_changed.connect(_on_stats_changed)
	StatsManager.resources_changed.connect(_on_resources_changed)
	StatsManager.day_advanced.connect(_on_day_advanced)
	StatsManager.day_consequences.connect(_on_day_consequences)
	StatsManager.educational_note.connect(_on_educational_note)
	StatsManager.forecast_ready.connect(_on_forecast_ready)
	StatsManager.emergency_protocol_availability_changed.connect(_on_emergency_availability_changed)
	StatsManager.mission_ended.connect(_on_mission_ended)

	repair_life_support_button.tooltip_text = ACTION_TOOLTIPS.life_support
	boost_power_button.tooltip_text = ACTION_TOOLTIPS.power
	reinforce_shield_button.tooltip_text = ACTION_TOOLTIPS.radiation_shield
	tend_food_button.tooltip_text = ACTION_TOOLTIPS.food_production

	repair_life_support_button.pressed.connect(func(): _do_action("life_support"))
	boost_power_button.pressed.connect(func(): _do_action("power"))
	reinforce_shield_button.pressed.connect(func(): _do_action("radiation_shield"))
	tend_food_button.pressed.connect(func(): _do_action("food_production"))
	end_day_button.pressed.connect(_on_end_day_pressed)
	restart_button.pressed.connect(_on_restart_pressed)

	debrief_panel.visible = false
	consequences_label.text = ""
	note_label.text = ""

	# Connect first, THEN start — start_mission() emits the SOL 1 morning
	# report, and we need to already be listening for it.
	StatsManager.start_mission()

## Fails immediately, naming the exact missing node, instead of a silent
## null-instance crash the first time that node is touched later on. If
## this fires: select the named node in the scene tree and enable
## "Access as Unique Name" (or re-add the node if it was renamed/deleted).
func _assert_required_nodes() -> void:
	var required := {
		"%LifeSupportBar": life_support_bar,
		"%PowerBar": power_bar,
		"%RadiationBar": radiation_bar,
		"%FoodBar": food_bar,
		"%LifeSupportBarLabel": life_support_bar_label,
		"%PowerBarLabel": power_bar_label,
		"%RadiationBarLabel": radiation_bar_label,
		"%FoodBarLabel": food_bar_label,
		"%DayLabel": day_label,
		"%ConsequencesLabel": consequences_label,
		"%MissionLogLabel": mission_log_label,
		"%NoteLabel": note_label,
		"%ResourcesLabel": resources_label,
		"%RepairLifeSupportButton": repair_life_support_button,
		"%BoostPowerButton": boost_power_button,
		"%ReinforceShieldButton": reinforce_shield_button,
		"%TendFoodButton": tend_food_button,
		"%EndDayButton": end_day_button,
		"%DebriefPanel": debrief_panel,
		"%DebriefLabel": debrief_label,
		"%RestartButton": restart_button,
	}
	for path in required.keys():
		assert(required[path] != null, "OutpostUI: required node missing — " + path + ". Check 'Access as Unique Name' is enabled for it in the scene.")

## Optional nodes that aren't part of the original node tree. Looked up
## defensively so their absence never crashes the scene — the corresponding
## feature (forecast line / emergency protocol button) just stays inactive.
func _wire_optional_nodes() -> void:
	forecast_label = get_node_or_null("%ForecastLabel")
	if forecast_label == null:
		print("OutpostUI: optional %ForecastLabel not found — forecast line will be skipped. Add a Label with this unique name to enable it.")

	emergency_button = get_node_or_null("%EmergencyButton")
	if emergency_button == null:
		print("OutpostUI: optional %EmergencyButton not found — emergency protocol will be skipped. Add a Button with this unique name to enable it.")
	else:
		emergency_button.pressed.connect(_on_emergency_button_pressed)

	chat_button = get_node_or_null("%ChatButton")
	chat_panel = get_node_or_null("%ChatPanel")
	chat_questions_container = get_node_or_null("%ChatQuestionsContainer")
	chat_response_label = get_node_or_null("%ChatResponseLabel")
	chat_close_button = get_node_or_null("%ChatCloseButton")

	if chat_button == null or chat_panel == null or chat_questions_container == null or chat_response_label == null:
		print("OutpostUI: chat assistant nodes not fully present — 'Ask Kasei' will be skipped. See README for the nodes to add (%ChatButton, %ChatPanel, %ChatQuestionsContainer, %ChatResponseLabel, optional %ChatCloseButton).")
	else:
		chat_panel.visible = false
		chat_response_label.text = "Tap a question below to ask Kasei!"
		chat_button.pressed.connect(_on_chat_button_pressed)
		if chat_close_button != null:
			chat_close_button.pressed.connect(_on_chat_close_pressed)
		_populate_chat_questions()

	chart_button = get_node_or_null("%ChartButton")
	chart_panel = get_node_or_null("%ChartPanel")
	chart_canvas = get_node_or_null("%ChartCanvas")
	chart_close_button = get_node_or_null("%ChartCloseButton")

	if chart_button == null or chart_panel == null or chart_canvas == null:
		print("OutpostUI: chart nodes not fully present — history chart will be skipped. Add %ChartButton, %ChartPanel, and a %ChartCanvas (Control with HistoryChart.gd attached) to enable it.")
	else:
		chart_panel.visible = false
		chart_button.pressed.connect(_on_chart_button_pressed)
		if chart_close_button != null:
			chart_close_button.pressed.connect(_on_chart_close_pressed)
		StatsManager.history_updated.connect(_on_history_updated)

	info_button = get_node_or_null("%InfoButton")
	info_panel = get_node_or_null("%InfoPanel")
	info_content_label = get_node_or_null("%InfoContentLabel")
	info_close_button = get_node_or_null("%InfoCloseButton")

	if info_button == null or info_panel == null or info_content_label == null:
		print("OutpostUI: info popup nodes not fully present — skipped. Add %InfoButton, %InfoPanel, and %InfoContentLabel to enable it.")
	else:
		info_panel.visible = false
		info_content_label.text = _build_action_cost_text()
		info_button.pressed.connect(_on_info_button_pressed)
		if info_close_button != null:
			info_close_button.pressed.connect(_on_info_close_pressed)

	undo_button = get_node_or_null("%UndoButton")
	if undo_button == null:
		print("OutpostUI: optional %UndoButton not found — undo will be skipped. Add a Button (or TextureButton) with this unique name to enable it.")
	else:
		undo_button.disabled = true
		undo_button.pressed.connect(_on_undo_button_pressed)
		StatsManager.undo_availability_changed.connect(_on_undo_availability_changed)

func _do_action(stat_name: String) -> void:
	if not StatsManager.perform_action(stat_name):
		mission_log_label.text = "Not enough energy/manpower for that action right now."

func _on_end_day_pressed() -> void:
	StatsManager.advance_day()

func _on_emergency_button_pressed() -> void:
	if not StatsManager.use_emergency_protocol():
		mission_log_label.text = "Emergency protocol already used this mission."

## Builds one Button per entry in AssistantEngine.QUESTIONS and drops it
## into %ChatQuestionsContainer. Fixed question set by design — see
## AssistantEngine.gd for why this isn't free-text input.
func _populate_chat_questions() -> void:
	for question in AssistantEngine.QUESTIONS:
		var button := Button.new()
		button.text = question.text
		button.pressed.connect(func(): _on_chat_question_pressed(question.id))
		chat_questions_container.add_child(button)

func _on_chat_button_pressed() -> void:
	chat_panel.visible = not chat_panel.visible

func _on_chat_close_pressed() -> void:
	chat_panel.visible = false

func _on_chat_question_pressed(question_id: String) -> void:
	chat_response_label.text = assistant_engine.answer(question_id)

func _on_chart_button_pressed() -> void:
	chart_panel.visible = not chart_panel.visible
	if chart_panel.visible:
		_refresh_chart()

func _on_chart_close_pressed() -> void:
	chart_panel.visible = false

func _on_history_updated(_history: Array) -> void:
	if chart_panel != null and chart_panel.visible:
		_refresh_chart()

## Rebuilds the four vital lines from StatsManager.history and hands them
## to %ChartCanvas. Vitals are already 0-100, so normalizing to 0..1 for
## HistoryChart is just a divide — no per-series scaling needed.
func _refresh_chart() -> void:
	var built: Array = []
	for key in CHART_SERIES_STYLES.keys():
		var values: Array = []
		for entry in StatsManager.history:
			values.append(float(entry[key]) / 100.0)
		var cfg: Dictionary = CHART_SERIES_STYLES[key]
		built.append({
			"label": key.capitalize().replace("_", " "),
			"color": cfg.color,
			"style": cfg.style,
			"values": values,
		})
	chart_canvas.set_series_list(built)

func _on_info_button_pressed() -> void:
	info_panel.visible = not info_panel.visible

func _on_info_close_pressed() -> void:
	info_panel.visible = false

## Static reference text built from the same cost data the action buttons
## already use — nothing new to maintain, just displayed differently.
func _build_action_cost_text() -> String:
	var lines: Array[String] = []
	lines.append("ACTION COSTS")
	lines.append("")
	for stat_name in ACTION_TOOLTIPS.keys():
		lines.append(ACTION_TOOLTIPS[stat_name])
	return "\n".join(lines)

func _on_undo_button_pressed() -> void:
	if not StatsManager.undo_last_action():
		mission_log_label.text = "Nothing to undo."

func _on_undo_availability_changed(available: bool) -> void:
	if undo_button != null:
		undo_button.disabled = not available

func _on_stats_changed(stats: Dictionary) -> void:
	life_support_bar.value = stats.life_support
	power_bar.value = stats.power
	radiation_bar.value = stats.radiation_shield
	food_bar.value = stats.food_production

	life_support_bar_label.text = "Life Support %d%%" % int(stats.life_support)
	power_bar_label.text = "Power %d%%" % int(stats.power)
	radiation_bar_label.text = "Shield %d%%" % int(stats.radiation_shield)
	food_bar_label.text = "Food %d%%" % int(stats.food_production)

	_refresh_telemetry_block()

func _on_resources_changed(energy: int, manpower: int) -> void:
	resources_label.text = "Energy: %d   Manpower: %d" % [energy, manpower]

	repair_life_support_button.disabled = not StatsManager.can_afford("life_support")
	boost_power_button.disabled = not StatsManager.can_afford("power")
	reinforce_shield_button.disabled = not StatsManager.can_afford("radiation_shield")
	tend_food_button.disabled = not StatsManager.can_afford("food_production")

	# Crew Available in the telemetry block depends on manpower_remaining,
	# which only this signal carries — refresh here too, not just on
	# stats_changed/day_advanced.
	_refresh_telemetry_block()

## DayLabel: just the header — SOL number, date, location. Rebuilt once
## per new SOL.
func _on_day_advanced(day_number: int, day_data: Dictionary) -> void:
	day_label.text = "SOL %d — %s\n%s" % [day_number, day_data.get("date", ""), DataLoader.location]
	_refresh_telemetry_block()

## MissionLogLabel: the always-current telemetry dashboard — temps,
## radiation, power, the derived flavor readouts, and crew. Rebuilt
## whenever any contributing signal fires, so it never goes stale while
## the player is mid-sol spending actions.
func _refresh_telemetry_block() -> void:
	var data := StatsManager.current_day_data
	if data.is_empty():
		return
	var stats: Dictionary = StatsManager.stats
	var surface_temp: float = data.get("surface_temp_c", 0.0)
	var sunlight_hours: float = data.get("sunlight_hours", 12.0)
	var radiation_dose: float = data.get("radiation_dose_rate", 0.0)

	var lines: Array[String] = []
	lines.append("SURFACE: %.0f°C" % surface_temp)
	lines.append("INTERIOR: %.0f°C" % _derived_interior_temp())
	lines.append("")
	lines.append("Radiation Dose: %.2f mGy" % radiation_dose)
	lines.append("Shield Integrity: %d%%" % int(stats.radiation_shield))
	lines.append("")
	lines.append("Solar Input: %d%%" % int(_derived_solar_input_pct(sunlight_hours)))
	lines.append("Battery Reserve: %d%%" % int(stats.power))
	lines.append("Sunlight Remaining: %.1f hrs" % sunlight_hours)
	lines.append("")
	lines.append("Oxygen: %.1f%%" % _derived_oxygen_pct())
	lines.append("CO2 Level: %d ppm" % int(_derived_co2_ppm()))
	lines.append("Water Reserve: %d%%" % int(_derived_water_pct()))
	lines.append("Food Reserve: %d days" % _derived_food_reserve_days())
	lines.append("")
	lines.append("Crew Available: %d / %d" % [StatsManager.manpower_remaining, StatsManager.MAX_MANPOWER])
	if data.get("is_gap_filled", false):
		lines.append("")
		lines.append("(Today's reading estimated from the last known values — a gap in the real data.)")
	mission_log_label.text = "\n".join(lines)

## ConsequencesLabel's detailed before/after breakdown doesn't fit this
## compact always-current layout — hidden rather than shown. The cause
## line still reaches the player via the alerts block below (NoteLabel).
func _on_day_consequences(_day_number: int, _before: Dictionary, _after: Dictionary, cause_text: String) -> void:
	consequences_label.visible = false
	latest_cause_text = cause_text
	_refresh_alerts_block()

func _on_educational_note(text: String) -> void:
	latest_note_text = text
	_refresh_alerts_block()

## NoteLabel: the bottom "alerts" block — cause line, educational note (if
## any), and the next-SOL forecast, one per line, matching the mockup's
## short bullet-style readout.
func _refresh_alerts_block() -> void:
	var lines: Array[String] = []
	if latest_cause_text != "":
		lines.append(latest_cause_text)
	if latest_note_text != "":
		lines.append(latest_note_text)
	if latest_forecast_text != "":
		lines.append(latest_forecast_text)
	note_label.text = "\n".join(lines)

## Optional: qualitative preview of tomorrow's conditions, shown next to
## today's morning report so the player can plan ahead. No-op if
## %ForecastLabel isn't in the scene.
func _on_forecast_ready(text: String) -> void:
	if forecast_label != null:
		forecast_label.text = text
	latest_forecast_text = text
	_refresh_alerts_block()

## Optional: enables/disables the emergency protocol button as it becomes
## unavailable (used once, or mission over). No-op if %EmergencyButton
## isn't in the scene.
func _on_emergency_availability_changed(available: bool) -> void:
	if emergency_button != null:
		emergency_button.disabled = not available

func _on_mission_ended(success: bool, summary: String) -> void:
	debrief_label.text = summary
	debrief_panel.visible = true

	end_day_button.disabled = true
	repair_life_support_button.disabled = true
	boost_power_button.disabled = true
	reinforce_shield_button.disabled = true
	tend_food_button.disabled = true
	if emergency_button != null:
		emergency_button.disabled = true
	if chat_button != null:
		chat_panel.visible = false
	if chart_button != null:
		chart_panel.visible = false
	if info_button != null:
		info_panel.visible = false
	if undo_button != null:
		undo_button.disabled = true

func _on_restart_pressed() -> void:
	debrief_panel.visible = false
	consequences_label.text = ""
	note_label.text = ""
	latest_cause_text = ""
	latest_note_text = ""
	latest_forecast_text = ""
	StatsManager.start_mission()
