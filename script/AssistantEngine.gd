class_name AssistantEngine
extends RefCounted
## "Ask Kasei" chat assistant — Option A from planning: a templated,
## dataset-grounded Q&A engine, NOT a general-purpose/LLM chatbot.
##
## Deliberately scoped this way for three reasons:
##   1. Every answer is deterministic and traceable straight back to the
##      real dataset — nothing invented, nothing off-topic.
##   2. No network calls, no API key to protect, nothing that can fail live
##      during a judged demo because of venue wifi or an API outage.
##   3. No free-text input from a child going anywhere near an open-ended
##      model — the question set is fixed and reviewed up front.
##
## Not an autoload. OutpostUI owns one instance (see `assistant_engine` in
## OutpostUI.gd) and calls answer(id) each time a question button is
## tapped. Reads live state directly from the StatsManager and DataLoader
## autoloads, so answers always reflect the CURRENT sol, not a snapshot.

## One entry per question button shown in the chat window, in display
## order. `id` is passed back to answer() when that button is tapped.
const QUESTIONS := [
	{"id": "radiation_today", "text": "What's today's radiation dose?"},
	{"id": "temp_today", "text": "What's today's temperature?"},
	{"id": "sunlight_today", "text": "What's today's sunlight like?"},
	{"id": "worst_vital", "text": "What should I focus on right now?"},
	{"id": "why_power", "text": "Why does Power matter so much?"},
	{"id": "why_life_support", "text": "Why is Life Support struggling?"},
	{"id": "why_food", "text": "Why does Food Production keep dropping?"},
	{"id": "why_shield", "text": "Why is my Radiation Shield low?"},
	{"id": "resources_explainer", "text": "How do Energy and Manpower work?"},
	{"id": "data_source", "text": "Where does this data come from?"},
]

func answer(question_id: String) -> String:
	match question_id:
		"radiation_today":
			return _radiation_today()
		"temp_today":
			return _temp_today()
		"sunlight_today":
			return _sunlight_today()
		"worst_vital":
			return _worst_vital()
		"why_power":
			return _why_power()
		"why_life_support":
			return _why_life_support()
		"why_food":
			return _why_food()
		"why_shield":
			return _why_shield()
		"resources_explainer":
			return _resources_explainer()
		"data_source":
			return _data_source()
		_:
			return "I don't have an answer for that one yet."

func _current_data() -> Dictionary:
	return StatsManager.current_day_data

func _radiation_today() -> String:
	var data := _current_data()
	if data.is_empty():
		return "No data loaded for today yet."
	var dose: float = data.get("radiation_dose_rate", 0.0)
	var line := "Today's radiation dose is %.2f — real data from Curiosity's RAD instrument." % dose
	if dose > StatsManager.NOTABLE_RADIATION_CAUSE:
		line += " That's high enough to drain your shield faster than usual — worth reinforcing it today."
	else:
		line += " That's a fairly calm reading — your shield should hold steady."
	return line

func _temp_today() -> String:
	var data := _current_data()
	if data.is_empty():
		return "No data loaded for today yet."
	var temp: float = data.get("surface_temp_c", 0.0)
	var line := "Today's surface temperature is %.0f°C — real data from Perseverance's MEDA weather station." % temp
	if temp < StatsManager.LIFE_SUPPORT_COLD_THRESHOLD:
		line += " That's extreme cold — it's putting extra strain on Life Support."
	return line

func _sunlight_today() -> String:
	var data := _current_data()
	if data.is_empty():
		return "No data loaded for today yet."
	var sun: float = data.get("sunlight_hours", 0.0)
	var line := "Today's sunlight is about %.1f hours." % sun
	if sun < StatsManager.LOW_SUN_CAUSE_THRESHOLD:
		line += " That's low — your solar panels won't generate much Power today."
	elif sun >= StatsManager.HIGH_SUN_CAUSE_THRESHOLD:
		line += " That's strong sunlight — a good day for Power generation."
	return line

func _worst_vital() -> String:
	var stats: Dictionary = StatsManager.stats
	var worst_key: String = stats.keys()[0]
	for key in stats.keys():
		if stats[key] < stats[worst_key]:
			worst_key = key
	var worst_name: String = worst_key.capitalize().replace("_", " ")
	return "%s is your weakest system right now, at %d%%. That's also why Kasei looks the way it does — the mascot always reacts to your worst system, not the average." % [worst_name, int(stats[worst_key])]

func _why_power() -> String:
	return "Power comes from sunlight, and it caps how much Energy you have to spend on repairs. When Power drops, everything else gets more expensive to fix — that's a real trade-off outposts actually face."

func _why_life_support() -> String:
	return "Life Support takes extra damage on extremely cold sols, and it caps how much Manpower (crew hours) you have. A struggling outpost genuinely has fewer hands to fix itself — that's intentional, not a bug."

func _why_food() -> String:
	return "Food Production depends on how much Power you have — less Power means less energy for growing systems. It's a knock-on effect from Power, not a separate problem on its own."

func _why_shield() -> String:
	return "Your Radiation Shield drains faster on high-radiation sols — that's real dose-rate data from Curiosity's RAD instrument driving the decay."

func _resources_explainer() -> String:
	return "Energy is capped by your current Power — low Power means less Energy to spend. Manpower is capped by Life Support, with a fatigue penalty if it drops too low. Both always keep a small minimum, so you're never completely stuck."

func _data_source() -> String:
	var lines: Array[String] = []
	if DataLoader.radiation_source != "":
		lines.append("Radiation — %s" % DataLoader.radiation_source)
	if DataLoader.temperature_source != "":
		lines.append("Temperature — %s" % DataLoader.temperature_source)
	if DataLoader.sunlight_note != "":
		lines.append("Sunlight — %s" % DataLoader.sunlight_note)
	if lines.is_empty():
		return DataLoader.location if DataLoader.location != "" else "Real NASA mission data — source details coming soon."
	return "\n".join(lines)
