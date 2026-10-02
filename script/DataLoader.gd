extends Node
## Autoload name: DataLoader
## Add this script as an Autoload in Project Settings > Autoload
## so any scene can access DataLoader.get_day(n) or DataLoader.days

var days: Array = []
var location: String = ""
var source_notes: String = ""

# Per-variable attribution, shown on the debrief screen. The dataset mixes
# two different rovers at two different craters plus a derived field, so
# this is disclosed explicitly rather than implied to be one clean feed.
# Populate these in mission_data.json; safe to leave blank while the file
# is still placeholder-shaped — the debrief just falls back to
# location/source_notes below if they're empty.
var radiation_source: String = ""
var temperature_source: String = ""
var sunlight_note: String = ""

const DATA_PATH := "res://data/mission_data.json"

# Fields carried forward from the previous SOL when missing/null in the
# source JSON, instead of silently falling back to StatsManager's
# hardcoded defaults (which read as "conditions were calm" — the opposite
# of what a real instrument gap usually means).
const CARRY_FORWARD_FIELDS := ["radiation_dose_rate", "surface_temp_c", "sunlight_hours"]

func _ready() -> void:
	_load_data()

func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("DataLoader: mission_data.json not found at " + DATA_PATH)
		return

	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("DataLoader: failed to parse mission_data.json")
		return

	days = parsed.get("days", [])
	location = parsed.get("location", "")
	source_notes = parsed.get("source_notes", "")
	radiation_source = parsed.get("radiation_source", "")
	temperature_source = parsed.get("temperature_source", "")
	sunlight_note = parsed.get("sunlight_note", "")

	_fill_data_gaps()

	print("DataLoader: loaded %d days of mission data for %s" % [days.size(), location])

## RAD and MEDA both have real coverage gaps. Rather than let a missing
## field silently read as StatsManager's hardcoded default, carry the last
## known real value forward and flag the day, so the UI can note it's a
## gap-filled reading instead of presenting it as a fresh measurement.
func _fill_data_gaps() -> void:
	var last_known := {}
	for day in days:
		day["is_gap_filled"] = false
		for field in CARRY_FORWARD_FIELDS:
			var value = day.get(field, null)
			if value == null:
				if last_known.has(field):
					day[field] = last_known[field]
					day["is_gap_filled"] = true
				# else: gap at the very start of the dataset, nothing to
				# carry forward yet — leave it out; StatsManager's .get()
				# default applies for that one field only, for that one day.
			else:
				last_known[field] = value

## Returns the data dict for a given 1-indexed day, or {} once you run past
## the end of the real dataset.
##
## IMPORTANT: this must NOT clamp to the last day. StatsManager treats an
## empty dict from get_day(current_day + 1) as "mission complete" — clamping
## here would make the mission repeat the final SOL's data forever and
## never reach the success screen.
func get_day(day_number: int) -> Dictionary:
	var index := day_number - 1
	if index < 0 or index >= days.size():
		return {}
	return days[index]

func total_days() -> int:
	return days.size()
