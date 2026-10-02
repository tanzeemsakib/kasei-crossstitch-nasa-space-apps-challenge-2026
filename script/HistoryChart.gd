class_name HistoryChart
extends Control
## A minimal line-graph canvas — no plugin, no external library, just
## Control._draw(). Deliberately dumb: it only knows how to draw lines from
## 0..1 values. Whoever calls set_series_list() (OutpostUI) is responsible
## for picking which stats to show and normalizing them — that keeps this
## node reusable for both the 0-100 vitals and, later, differently-scaled
## environment readings (radiation dose, temp, sunlight) if you want a
## second chart for those.
##
## Usage:
##   chart_canvas.set_series_list([
##       {"label": "Power", "color": Color(0.95, 0.8, 0.3), "values": [0.8, 0.75, ...]},
##       ...
##   ])
## Each series' `values` should already be clamped/normalized to 0..1;
## anything outside that range is clamped when drawn.

var series: Array = []

const MARGIN := 16.0
const LINE_WIDTH := 3.0
const GRID_LINES := 4
const POINT_RADIUS := 3.0

# Line styles, for telling series apart without relying on different
# colors (e.g. when every line shares one palette color). Each pattern is
# an array of alternating on/off lengths in pixels, starting with "on".
const DASH_PATTERNS := {
	"dashed": [14.0, 8.0],
	"dash_dot": [14.0, 6.0, 2.0, 6.0],
}
const DOTTED_SPACING := 10.0
const DOTTED_RADIUS := 2.0

func set_series_list(new_series: Array) -> void:
	series = new_series
	queue_redraw()

func _draw() -> void:
	var plot_rect := Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2)

	# Background fill — matches the palette's button/bar purple so the
	# chart reads as part of the same design system, not a generic canvas.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#A070A1"))

	# Horizontal gridlines (0%, 25%, 50%, 75%, 100% by default).
	for i in range(GRID_LINES + 1):
		var y := plot_rect.position.y + plot_rect.size.y * (float(i) / GRID_LINES)
		draw_line(Vector2(plot_rect.position.x, y), Vector2(plot_rect.end.x, y), Color(1, 1, 1, 0.08), 1.0)

	for s in series:
		var values: Array = s.get("values", [])
		if values.size() < 2:
			continue
		var color: Color = s.get("color", Color.WHITE)
		var line_style: String = s.get("style", "solid")
		var points := PackedVector2Array()
		for i in range(values.size()):
			var x := plot_rect.position.x + plot_rect.size.x * (float(i) / float(max(1, values.size() - 1)))
			var y := plot_rect.end.y - clampf(values[i], 0.0, 1.0) * plot_rect.size.y
			points.append(Vector2(x, y))

		if line_style == "dotted":
			_draw_dotted_polyline(points, color)
		elif DASH_PATTERNS.has(line_style):
			_draw_patterned_polyline(points, color, DASH_PATTERNS[line_style])
		else:
			draw_polyline(points, color, LINE_WIDTH, true)

		# Small dot on the final point — makes "today" easy to spot at a glance.
		draw_circle(points[points.size() - 1], POINT_RADIUS * 1.6, color)

## Draws a line following `points`, alternating on/off according to
## `pattern` (lengths in pixels, starting "on"). Works across multiple
## connected segments, not just within one — the pattern continues
## seamlessly from one point-to-point segment into the next.
func _draw_patterned_polyline(points: PackedVector2Array, color: Color, pattern: Array) -> void:
	var pattern_index := 0
	var pattern_remaining: float = pattern[0]
	var drawing := true
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg_vec := b - a
		var seg_len := seg_vec.length()
		if seg_len <= 0.0:
			continue
		var dir := seg_vec / seg_len
		var seg_pos := 0.0
		while seg_pos < seg_len:
			var step: float = min(pattern_remaining, seg_len - seg_pos)
			if drawing:
				draw_line(a + dir * seg_pos, a + dir * (seg_pos + step), color, LINE_WIDTH)
			seg_pos += step
			pattern_remaining -= step
			if pattern_remaining <= 0.001:
				pattern_index = (pattern_index + 1) % pattern.size()
				pattern_remaining = pattern[pattern_index]
				drawing = not drawing

## Draws evenly-spaced dots along `points` instead of a continuous line.
func _draw_dotted_polyline(points: PackedVector2Array, color: Color) -> void:
	draw_circle(points[0], DOTTED_RADIUS, color)
	var dist_since_last_dot := 0.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg_vec := b - a
		var seg_len := seg_vec.length()
		if seg_len <= 0.0:
			continue
		var dir := seg_vec / seg_len
		var seg_pos := 0.0
		while seg_pos < seg_len:
			var remaining_to_dot: float = DOTTED_SPACING - dist_since_last_dot
			if remaining_to_dot <= seg_len - seg_pos:
				seg_pos += remaining_to_dot
				draw_circle(a + dir * seg_pos, DOTTED_RADIUS, color)
				dist_since_last_dot = 0.0
			else:
				dist_since_last_dot += seg_len - seg_pos
				seg_pos = seg_len
