extends Node
## Autoload name: StatsManager
## The tamagotchi "vitals" for the outpost.
##
## Flow per SOL (day):
##   1. start_mission() / previous End Day leaves current_day_data loaded —
##      this is the "morning report" for the active SOL (radiation, temp,
##      sunlight) shown BEFORE any decay happens. A one-line forecast for
##      the SOL AFTER that is emitted alongside it, so the player can plan
##      ahead instead of only reacting after the fact.
##   2. Player spends Energy + Manpower (capped by current Power / Life
##      Support, with a guaranteed floor on both — see MIN_ENERGY /
##      MIN_MANPOWER) on care actions. A once-per-mission Emergency
##      Protocol is also available as a safety valve.
##   3. Player presses End Day -> advance_day() applies that SOL's real
##      environmental decay, emits a before/after "consequences" breakdown
##      with a plain-language cause line, THEN loads and shows the next
##      SOL's morning report + forecast.
##
## This keeps cause (real data) -> effect (decay) -> consequence (visible
## breakdown) -> next decision clearly separated on screen, instead of
## burying the decay inside the next day's numbers.

signal stats_changed(stats: Dictionary)
signal resources_changed(energy: int, manpower: int)
signal day_advanced(day_number: int, day_data: Dictionary)
signal day_consequences(day_number: int, before: Dictionary, after: Dictionary, cause_text: String)
signal educational_note(text: String)
signal forecast_ready(text: String)
signal emergency_protocol_availability_changed(available: bool)
signal mission_ended(success: bool, summary: String)
signal history_updated(history: Array)
signal undo_availability_changed(available: bool)

# --- Tunable balance knobs ---
const MAX_STAT := 100.0
const FAIL_THRESHOLD := 0.0
const ACTION_RESTORE_AMOUNT := 18.0

const MAX_ENERGY := 6
const MAX_MANPOWER := 4
const MANPOWER_FATIGUE_THRESHOLD := 40.0

# A struggling outpost should have LESS capacity to recover — that's the
# intended tension — but never ZERO capacity, or one bad SOL becomes an
# un-recoverable spiral the player can't act their way out of. These are
# hard floors under the Power/Life-Support-derived pools below.
const MIN_ENERGY := 1
const MIN_MANPOWER := 1

# One-time safety valve on top of the floors above: fully restores whichever
# vital is currently worst, at a moderate cost to the other three. Doesn't
# remove the consequence of neglect, just gives the player one recovery
# swing before a spiral becomes unrecoverable.
const EMERGENCY_PROTOCOL_COST := 15.0

const ACTION_COSTS := {
	"life_support": {"energy": 1, "manpower": 2},
	"power": {"energy": 0, "manpower": 2},
	"radiation_shield": {"energy": 2, "manpower": 1},
	"food_production": {"energy": 1, "manpower": 1},
}

const RADIATION_DECAY_MULT := 40.0
const POWER_SUNLIGHT_DIVISOR := 24.0
const POWER_BASE_DRAIN := 12.0
const LIFE_SUPPORT_COLD_THRESHOLD := -175.0
const LIFE_SUPPORT_COLD_DRAIN_MULT := 0.6

# Deeper "real science" note thresholds (rarer, more extreme than the
# everyday cause-line thresholds below).
const RADIATION_NOTE_THRESHOLD := 0.55
const COLD_NOTE_THRESHOLD := -185.0
const LOW_SUN_NOTE_THRESHOLD := 3.0

# Everyday cause-line thresholds — these fire most days, to narrate the
# ordinary mechanical chain (e.g. "low sunlight reduced power"). Also
# reused (predictively) to build the next-SOL forecast line.
const LOW_SUN_CAUSE_THRESHOLD := 15.0
const HIGH_SUN_CAUSE_THRESHOLD := 20.0
const NOTABLE_RADIATION_CAUSE := 0.45
const NOTABLE_POWER_DROP := 5.0

var current_day: int = 0
var current_day_data: Dictionary = {}
var energy_remaining: int = MAX_ENERGY
var manpower_remaining: int = MAX_MANPOWER
var mission_over: bool = false
var emergency_protocol_used: bool = false

# One entry per completed sol: that sol's real environmental data plus the
# vitals that resulted from it. Powers an optional in-game history chart —
# see HistoryChart.gd / OutpostUI.gd's chart wiring. Each entry:
# {day, radiation_dose_rate, surface_temp_c, sunlight_hours,
#  life_support, power, radiation_shield, food_production}
var history: Array = []

# One-level undo: the most recent perform_action() this sol, if any hasn't
# been undone or cleared by ending the day yet. {} means nothing to undo.
var last_action: Dictionary = {}

var stats := {
	"life_support": 100.0,
	"power": 100.0,
	"radiation_shield": 100.0,
	"food_production": 100.0,
}

## Call once from the UI's _ready(), AFTER connecting to the signals above,
## so the first morning report isn't emitted before anything is listening.
## Also used to restart a fresh playthrough.
func start_mission() -> void:
	current_day = 1
	mission_over = false
	emergency_protocol_used = false
	history = []
	last_action = {}
	for key in stats.keys():
		stats[key] = MAX_STAT

	current_day_data = DataLoader.get_day(current_day)
	_recalculate_resource_pools()
	stats_changed.emit(stats)
	day_advanced.emit(current_day, current_day_data)
	emergency_protocol_availability_changed.emit(can_use_emergency_protocol())
	history_updated.emit(history)
	undo_availability_changed.emit(can_undo_last_action())
	_emit_forecast()

## Call this from the "End Day / Sleep" button.
func advance_day() -> void:
	if mission_over or current_day_data.is_empty():
		return

	last_action = {}
	undo_availability_changed.emit(false)

	var data := current_day_data
	var before := stats.duplicate()
	_apply_daily_decay(data)
	var after := stats.duplicate()

	history.append({
		"day": current_day,
		"radiation_dose_rate": data.get("radiation_dose_rate", 0.0),
		"surface_temp_c": data.get("surface_temp_c", 0.0),
		"sunlight_hours": data.get("sunlight_hours", 12.0),
		"life_support": after.life_support,
		"power": after.power,
		"radiation_shield": after.radiation_shield,
		"food_production": after.food_production,
	})
	history_updated.emit(history)

	var cause_text := _build_cause_line(data, before, after)
	day_consequences.emit(current_day, before, after, cause_text)

	var note := _get_educational_note(data)
	if note != "":
		educational_note.emit(note)
	else:
		educational_note.emit("")

	_recalculate_resource_pools()

	for key in stats.keys():
		if stats[key] <= FAIL_THRESHOLD:
			_end_mission(false, "%s reached zero on SOL %d." % [key.capitalize(), current_day])
			return

	current_day += 1
	var next_data := DataLoader.get_day(current_day)
	if next_data.is_empty():
		_end_mission(true, "Completed the full mission log — %d SOLs survived." % (current_day - 1))
		return

	current_day_data = next_data
	day_advanced.emit(current_day, current_day_data)
	_emit_forecast()

func _apply_daily_decay(data: Dictionary) -> void:
	var radiation_dose: float = data.get("radiation_dose_rate", 0.5)
	var sunlight_hours: float = data.get("sunlight_hours", 12.0)
	var surface_temp: float = data.get("surface_temp_c", -170.0)

	stats.radiation_shield -= radiation_dose * RADIATION_DECAY_MULT

	var generated := (sunlight_hours / POWER_SUNLIGHT_DIVISOR) * 30.0
	stats.power -= (POWER_BASE_DRAIN - generated)

	var cold_penalty := 0.0
	if surface_temp < LIFE_SUPPORT_COLD_THRESHOLD:
		cold_penalty = (LIFE_SUPPORT_COLD_THRESHOLD - surface_temp) * LIFE_SUPPORT_COLD_DRAIN_MULT
	stats.life_support -= (8.0 + cold_penalty)

	var power_fraction: float = clampf(stats.power / MAX_STAT, 0.0, 1.0)
	stats.food_production -= (10.0 - power_fraction * 8.0)

	for key in stats.keys():
		stats[key] = clampf(stats[key], 0.0, MAX_STAT)

	stats_changed.emit(stats)

func _recalculate_resource_pools() -> void:
	var power_fraction: float = clampf(stats.power / MAX_STAT, 0.0, 1.0)
	energy_remaining = maxi(MIN_ENERGY, int(round(MAX_ENERGY * power_fraction)))

	manpower_remaining = MAX_MANPOWER
	if stats.life_support < MANPOWER_FATIGUE_THRESHOLD:
		manpower_remaining = MAX_MANPOWER - 1
	manpower_remaining = maxi(MIN_MANPOWER, manpower_remaining)

	resources_changed.emit(energy_remaining, manpower_remaining)

func perform_action(stat_name: String) -> bool:
	if mission_over:
		return false
	if not stats.has(stat_name) or not ACTION_COSTS.has(stat_name):
		push_warning("Unknown stat: " + stat_name)
		return false

	var cost: Dictionary = ACTION_COSTS[stat_name]
	if energy_remaining < cost.energy or manpower_remaining < cost.manpower:
		return false

	energy_remaining -= cost.energy
	manpower_remaining -= cost.manpower
	stats[stat_name] = clampf(stats[stat_name] + ACTION_RESTORE_AMOUNT, 0.0, MAX_STAT)

	last_action = {"stat_name": stat_name, "energy": cost.energy, "manpower": cost.manpower}
	undo_availability_changed.emit(true)

	stats_changed.emit(stats)
	resources_changed.emit(energy_remaining, manpower_remaining)
	return true

func can_undo_last_action() -> bool:
	return not mission_over and not last_action.is_empty()

## Reverses the most recent perform_action() this sol: refunds its Energy
## and Manpower cost and un-does its stat restore. One level deep only —
## calling this twice in a row without a new action in between does
## nothing the second time. Cleared automatically when the day ends, since
## undoing into a previous sol wouldn't make sense once its decay has
## already been applied and shown to the player.
func undo_last_action() -> bool:
	if not can_undo_last_action():
		return false

	var stat_name: String = last_action.stat_name
	stats[stat_name] = clampf(stats[stat_name] - ACTION_RESTORE_AMOUNT, 0.0, MAX_STAT)
	energy_remaining += last_action.energy
	manpower_remaining += last_action.manpower
	last_action = {}

	stats_changed.emit(stats)
	resources_changed.emit(energy_remaining, manpower_remaining)
	undo_availability_changed.emit(false)
	return true

func can_afford(stat_name: String) -> bool:
	if not ACTION_COSTS.has(stat_name):
		return false
	var cost: Dictionary = ACTION_COSTS[stat_name]
	return energy_remaining >= cost.energy and manpower_remaining >= cost.manpower

func can_use_emergency_protocol() -> bool:
	return not mission_over and not emergency_protocol_used

## Once-per-mission safety valve: fully restores whichever vital is
## currently worst, at a moderate cost to the other three. Hook this up to
## an optional button in the UI — see OutpostUI.gd's handling of
## %EmergencyButton, which wires it only if that node exists in the scene.
func use_emergency_protocol() -> bool:
	if not can_use_emergency_protocol():
		return false
	emergency_protocol_used = true

	var worst_key: String = stats.keys()[0]
	for key in stats.keys():
		if stats[key] < stats[worst_key]:
			worst_key = key

	for key in stats.keys():
		if key == worst_key:
			stats[key] = MAX_STAT
		else:
			stats[key] = clampf(stats[key] - EMERGENCY_PROTOCOL_COST, 0.0, MAX_STAT)

	stats_changed.emit(stats)
	_recalculate_resource_pools()
	emergency_protocol_availability_changed.emit(can_use_emergency_protocol())
	return true

## Everyday mechanical explanation of what drove today's numbers — this is
## what powers the "SOL X CONSEQUENCES" cause line, e.g. "Low sunlight
## reduced power generation. Reduced power also affected food production."
func _build_cause_line(data: Dictionary, before: Dictionary, after: Dictionary) -> String:
	var radiation_dose: float = data.get("radiation_dose_rate", 0.0)
	var surface_temp: float = data.get("surface_temp_c", 0.0)
	var sunlight_hours: float = data.get("sunlight_hours", 12.0)

	var power_delta: float = after.power - before.power
	var food_delta: float = after.food_production - before.food_production
	var shield_delta: float = after.radiation_shield - before.radiation_shield
	var life_delta: float = after.life_support - before.life_support

	var candidates: Array = []

	if sunlight_hours < LOW_SUN_CAUSE_THRESHOLD:
		candidates.append({"priority": absf(power_delta), "text": "Low sunlight reduced power generation."})
	elif sunlight_hours >= HIGH_SUN_CAUSE_THRESHOLD:
		candidates.append({"priority": absf(power_delta) * 0.5, "text": "Strong sunlight kept power generation steady."})

	if power_delta <= -NOTABLE_POWER_DROP:
		candidates.append({"priority": absf(food_delta), "text": "Reduced power also affected food production."})

	if radiation_dose > NOTABLE_RADIATION_CAUSE:
		candidates.append({"priority": absf(shield_delta), "text": "Elevated radiation drained the shield."})

	if surface_temp < LIFE_SUPPORT_COLD_THRESHOLD:
		candidates.append({"priority": absf(life_delta), "text": "Extreme cold strained life support."})

	if data.get("is_gap_filled", false):
		candidates.append({"priority": -1.0, "text": "(Today's reading fills a gap in the real data using the last known values.)"})

	if candidates.is_empty():
		return "Conditions were stable today."

	candidates.sort_custom(func(a, b): return a.priority > b.priority)
	var top: Array = candidates.slice(0, mini(2, candidates.size()))
	var texts: Array = []
	for c in top:
		texts.append(c.text)
	return " ".join(texts)

## Rarer, more extreme "real science" note — separate from the everyday
## cause line, for the standout days.
func _get_educational_note(data: Dictionary) -> String:
	var radiation_dose: float = data.get("radiation_dose_rate", 0.0)
	var surface_temp: float = data.get("surface_temp_c", 0.0)
	var sunlight_hours: float = data.get("sunlight_hours", 12.0)

	if radiation_dose >= RADIATION_NOTE_THRESHOLD:
		return "Radiation spike today — this is what a solar particle event looks like in real LRO CRaTER data. It's why crewed missions need thick shielding, not just for background cosmic rays."
	if surface_temp <= COLD_NOTE_THRESHOLD:
		return "That's colder than the coldest recorded temperature on Earth. Near the lunar poles, permanently shadowed craters barely warm up at all — real thermal insulation has to survive this."
	if sunlight_hours <= LOW_SUN_NOTE_THRESHOLD:
		return "Almost no sunlight today. Near the lunar south pole, crater shadows can last for weeks — solar panels alone can't guarantee power, which is why real missions plan battery reserves or nuclear power sources."
	return ""

## Qualitative, non-numeric preview of the NEXT SOL (current_day + 1),
## shown alongside today's morning report so the player can plan ahead
## instead of only reacting after End Day. Deliberately vague — it hints
## at what's coming without spoiling the exact numbers the real data will
## reveal.
func _build_forecast(next_data: Dictionary) -> String:
	if next_data.is_empty():
		return ""

	var radiation_dose: float = next_data.get("radiation_dose_rate", 0.0)
	var surface_temp: float = next_data.get("surface_temp_c", 0.0)
	var sunlight_hours: float = next_data.get("sunlight_hours", 12.0)

	var hints: Array[String] = []
	if radiation_dose > NOTABLE_RADIATION_CAUSE:
		hints.append("elevated radiation")
	if surface_temp < LIFE_SUPPORT_COLD_THRESHOLD:
		hints.append("extreme cold")
	if sunlight_hours < LOW_SUN_CAUSE_THRESHOLD:
		hints.append("low sunlight")
	elif sunlight_hours >= HIGH_SUN_CAUSE_THRESHOLD:
		hints.append("strong sunlight")

	if hints.is_empty():
		return "Forecast for SOL %d: conditions look steady." % (current_day + 1)
	return "Forecast for SOL %d: expect %s." % [current_day + 1, ", ".join(hints)]

func _emit_forecast() -> void:
	var next_data := DataLoader.get_day(current_day + 1)
	forecast_ready.emit(_build_forecast(next_data))

func _end_mission(success: bool, cause: String) -> void:
	mission_over = true
	var summary := _build_debrief(success, cause)
	mission_ended.emit(success, summary)

func _build_debrief(success: bool, cause: String) -> String:
	var lines: Array[String] = []
	lines.append("MISSION SUCCESS" if success else "MISSION FAILED")
	lines.append(cause)
	lines.append("SOLs survived: %d" % current_day)
	lines.append("")
	lines.append("Final vitals:")
	for key in stats.keys():
		lines.append("  %s: %d%%" % [key.capitalize().replace("_", " "), int(stats[key])])
	lines.append("")
	lines.append(_build_data_source_lines())
	return "\n".join(lines)

## Discloses the mixed-source, partly-derived nature of the dataset (two
## rovers, two craters, one derived field) instead of implying it's one
## clean feed. Falls back to the older single location/source_notes fields
## if mission_data.json hasn't been updated with per-variable attribution
## yet.
func _build_data_source_lines() -> String:
	var lines: Array[String] = []
	if DataLoader.radiation_source != "" or DataLoader.temperature_source != "":
		lines.append("Data sources:")
		if DataLoader.radiation_source != "":
			lines.append("  Radiation — %s" % DataLoader.radiation_source)
		if DataLoader.temperature_source != "":
			lines.append("  Temperature — %s" % DataLoader.temperature_source)
		if DataLoader.sunlight_note != "":
			lines.append("  Sunlight — %s" % DataLoader.sunlight_note)
	elif DataLoader.location != "":
		lines.append("Data source: %s" % DataLoader.location)
	if DataLoader.source_notes != "":
		lines.append(DataLoader.source_notes)
	return "\n".join(lines)
