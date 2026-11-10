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

# Short player-facing statement that the data is archived, not live, with
# the instrument and date range. Shown in the Info popup and on the debrief.
var archive_note: String = ""

const DATA_PATH := "res://data/mission_data.json"

# Fields carried forward from the previous SOL when missing/null in the
# source JSON, instead of silently falling back to StatsManager's
# hardcoded defaults (which read as "conditions were calm" — the opposite
# of what a real instrument gap usually means).
const CARRY_FORWARD_FIELDS := ["radiation_dose_rate", "surface_temp_c", "sunlight_hours"]

# Last-resort fallback when a field has NO prior real value to carry
# forward at all (a gap at the very start of the dataset — exactly the
# case while surface_temp_c/sunlight_hours are still JSON `null`
# placeholders pending a second real dataset). These are placeholder
# numbers, not real data — replace this field in mission_data.json with
# real values as soon as you have them, rather than relying on this.
const FIELD_FALLBACK_DEFAULTS := {
	"radiation_dose_rate": 0.0,
	"surface_temp_c": -60.0,
	"sunlight_hours": 12.0,
}

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
	archive_note = parsed.get("archive_note", "")

	_fill_data_gaps()

	print("DataLoader: loaded %d days of mission data for %s" % [days.size(), location])

## Instruments like RAD and MEDA both have real coverage gaps. Rather than let a missing
## field silently read as StatsManager's hardcoded default, carry the last
## known real value forward and flag the day, so the UI can note it's a
## gap-filled reading instead of presenting it as a fresh measurement.
func _fill_data_gaps() -> void:
	var last_known := {}
	for day in days:
		day["is_gap_filled"] = false
		# Which specific fields were filled, so the UI/assistant can be honest
		# per field (e.g. radiation is real but temperature is a placeholder).
		day["filled_fields"] = []
		for field in CARRY_FORWARD_FIELDS:
			var value = day.get(field, null)
			if value == null:
				if last_known.has(field):
					day[field] = last_known[field]
				else:
					# Gap at the very start of the dataset — nothing real to
					# carry forward yet. IMPORTANT: we must still write an
					# explicit numeric value here, not leave the key as
					# null. Dictionary.get(key, default) only falls back to
					# `default` when a key is MISSING entirely — if the key
					# exists with value null (as it does here, straight from
					# JSON), .get() returns null regardless of the default
					# you pass it, which crashes the first float read.
					day[field] = FIELD_FALLBACK_DEFAULTS.get(field, 0.0)
				day["is_gap_filled"] = true
				day["filled_fields"].append(field)
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
