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

@onready var repair_life_support_button: Button = %RepairLifeSupportButton
@onready var boost_power_button: Button = %BoostPowerButton
@onready var reinforce_shield_button: Button = %ReinforceShieldButton
@onready var tend_food_button: Button = %TendFoodButton
@onready var end_day_button: Button = %EndDayButton

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

const ACTION_LABELS := {
	"life_support": "Life Support\n1 Energy · 2 Crew",
	"power": "Power\n0 Energy · 2 Crew",
	"radiation_shield": "Shield\n2 Energy · 1 Crew",
	"food_production": "Food\n1 Energy · 1 Crew",
}

const ACTION_TOOLTIPS := {
	"life_support": "Repair Life Support (1 Energy, 2 Crew)",
	"power": "Boost Power (0 Energy, 2 Crew)",
	"radiation_shield": "Reinforce Shield (2 Energy, 1 Crew)",
	"food_production": "Tend Food (1 Energy, 1 Crew)",
}

# Display order for the consequences breakdown, matching the
# "SOL X CONSEQUENCES" format: Power, Food Production, Shield, Life Support.
const CONSEQUENCE_ROWS := [
	{"key": "power", "label": "Power"},
	{"key": "food_production", "label": "Food Production"},
	{"key": "radiation_shield", "label": "Shield"},
	{"key": "life_support", "label": "Life Support"},
]

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

	repair_life_support_button.text = ACTION_LABELS.life_support
	repair_life_support_button.tooltip_text = ACTION_TOOLTIPS.life_support
	boost_power_button.text = ACTION_LABELS.power
	boost_power_button.tooltip_text = ACTION_TOOLTIPS.power
	reinforce_shield_button.text = ACTION_LABELS.radiation_shield
	reinforce_shield_button.tooltip_text = ACTION_TOOLTIPS.radiation_shield
	tend_food_button.text = ACTION_LABELS.food_production
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

func _do_action(stat_name: String) -> void:
	if not StatsManager.perform_action(stat_name):
		mission_log_label.text = "Not enough energy/manpower for that action right now."

func _on_end_day_pressed() -> void:
	StatsManager.advance_day()

func _on_emergency_button_pressed() -> void:
	if not StatsManager.use_emergency_protocol():
		mission_log_label.text = "Emergency protocol already used this mission."

func _on_stats_changed(stats: Dictionary) -> void:
	life_support_bar.value = stats.life_support
	power_bar.value = stats.power
	radiation_bar.value = stats.radiation_shield
	food_bar.value = stats.food_production

	life_support_bar_label.text = "Life Support %d%%" % int(stats.life_support)
	power_bar_label.text = "Power %d%%" % int(stats.power)
	radiation_bar_label.text = "Shield %d%%" % int(stats.radiation_shield)
	food_bar_label.text = "Food %d%%" % int(stats.food_production)

func _on_resources_changed(energy: int, manpower: int) -> void:
	resources_label.text = "Energy: %d   Manpower: %d" % [energy, manpower]

	repair_life_support_button.disabled = not StatsManager.can_afford("life_support")
	boost_power_button.disabled = not StatsManager.can_afford("power")
	reinforce_shield_button.disabled = not StatsManager.can_afford("radiation_shield")
	tend_food_button.disabled = not StatsManager.can_afford("food_production")

## The NEW SOL's morning report — radiation/temp/sunlight the player is
## about to face, shown before they spend actions or end the day.
func _on_day_advanced(day_number: int, day_data: Dictionary) -> void:
	day_label.text = "SOL %d — %s" % [day_number, day_data.get("date", "")]
	var reading_text := "Today's readings — Radiation: %.2f | Temp: %.0f°C | Sunlight: %.1fh — %s" % [
		day_data.get("radiation_dose_rate", 0.0),
		day_data.get("surface_temp_c", 0.0),
		day_data.get("sunlight_hours", 0.0),
		DataLoader.location,
	]
	if day_data.get("is_gap_filled", false):
		reading_text += "\n(Estimated from the last known values — a gap in the real data.)"
	mission_log_label.text = reading_text

## The PREVIOUS SOL's before/after breakdown — shown right after End Day,
## before the next SOL's morning report replaces day_label/mission_log.
func _on_day_consequences(day_number: int, before: Dictionary, after: Dictionary, cause_text: String) -> void:
	var lines: Array[String] = []
	lines.append("SOL %d CONSEQUENCES" % day_number)
	for row in CONSEQUENCE_ROWS:
		var key: String = row.key
		lines.append("%s: %d → %d" % [row.label, int(before[key]), int(after[key])])
	lines.append("")
	lines.append(cause_text)
	consequences_label.text = "\n".join(lines)

func _on_educational_note(text: String) -> void:
	note_label.text = text

## Optional: qualitative preview of tomorrow's conditions, shown next to
## today's morning report so the player can plan ahead. No-op if
## %ForecastLabel isn't in the scene.
func _on_forecast_ready(text: String) -> void:
	if forecast_label != null:
		forecast_label.text = text

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

func _on_restart_pressed() -> void:
	debrief_panel.visible = false
	consequences_label.text = ""
	note_label.text = ""
	StatsManager.start_mission()
