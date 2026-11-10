extends Control
## Attach to a Control node with two children (see SETUP.md):
##   ModelHolder (Control > AnimatedSprite2D) — shows sprite-sheet animation once frames exist
##   FaceLabel (Label)                        — emoji fallback, used until animations exist
##
## The base's "face" reflects whichever vital is currently WORST, not the
## average — a thriving base with one system critically low still looks
## distressed. That's the point: one neglected system drags the whole
## outpost down, which is the actual lesson the challenge wants taught.
##
## IMPORTANT — reads nodes by %UniqueName instead of $Path. Enable
## "Access as Unique Name" (right-click -> Access as Unique Name) on
## ModelSprite, FaceLabel, and ModelHolder in the scene. Each is also
## asserted non-null in _ready(), so a missing/renamed node fails loudly
## with its exact name instead of a silent null-instance crash later.

@onready var model_sprite: AnimatedSprite2D = %ModelSprite
@onready var face_label: Label = %FaceLabel
@onready var model_holder: Control = %ModelHolder

# Optional: the small portrait box. Assign a TextureRect to this in the
# Inspector (select the CharacterPortrait node, drag the TextureRect onto
# "Portrait Rect"). Left empty, the portrait is simply skipped.
@export var portrait_rect: TextureRect

# Portrait crop, in the 557x634 art canvas, as Vector3(center_x, top_y, width).
# The crop HEIGHT is worked out from the portrait box's own shape, so the
# box can be any proportions (square, tall...) without stretching the art.
# The crop starts at top_y and runs downward, so a tall box shows head and
# shoulders, cut off at the bottom edge like a bust shot. The slumped
# FAILED pose sits lower on the canvas, so it gets its own values.
# To zoom in, make width smaller. To move it, change center_x / top_y.
const PORTRAIT_CROP_DEFAULT := Vector3(265, 70, 400)
const PORTRAIT_CROP_FAILED := Vector3(290, 190, 400)

# Which frame of each state's animation the portrait shows:
# 0 = first frame, 1 = second frame.
const PORTRAIT_FRAME := 1

var _last_state: State = State.STABLE
var _last_anim: String = ""

enum State { THRIVING, STABLE, STRAINED, CRITICAL, FAILED, SUCCESS }

# Add animations with these exact names to model_sprite's SpriteFrames
# and they'll be used automatically instead of the emoji fallback.
# No code changes needed.
const STATE_ANIM_NAMES := {
	State.THRIVING: "thriving",
	State.STABLE: "stable",
	State.STRAINED: "strained",
	State.CRITICAL: "critical",
	State.FAILED: "failed",
	State.SUCCESS: "success",
}

const STATE_EMOJI := {
	State.THRIVING: "(^‿^)",
	State.STABLE: "(•‿•)",
	State.STRAINED: "(•_•;)",
	State.CRITICAL: "(×_×;)",
	State.FAILED: "(×_×)",
	State.SUCCESS: "★(^‿^)★",
}

# Bottleneck thresholds — tune during playtesting.
const THRIVING_THRESHOLD := 70.0
const STABLE_THRESHOLD := 45.0
const STRAINED_THRESHOLD := 20.0

func _ready() -> void:
	_assert_required_nodes()

	_fit_sprite_to_holder()
	model_holder.resized.connect(_fit_sprite_to_holder)
	if portrait_rect != null:
		portrait_rect.resized.connect(_on_portrait_resized)
	StatsManager.stats_changed.connect(_on_stats_changed)
	StatsManager.mission_ended.connect(_on_mission_ended)
	_on_stats_changed(StatsManager.stats)

## Scales the sprite so a whole frame fits inside ModelHolder, keeping its
## aspect ratio, and centres it. All art frames share one canvas size
## (557x634), so one scale works for every state. Replaces the old fixed
## 3x scale, which would make a 557x634 frame far bigger than the holder.
## Re-runs whenever the holder is resized.
const FRAME_SIZE := Vector2(557, 634)

func _fit_sprite_to_holder() -> void:
	if model_holder.size.x <= 0.0 or model_holder.size.y <= 0.0:
		return
	var fit: float = min(model_holder.size.x / FRAME_SIZE.x, model_holder.size.y / FRAME_SIZE.y)
	model_sprite.scale = Vector2(fit, fit)
	model_sprite.position = model_holder.size / 2.0

## Fails immediately, naming the exact missing node, instead of a silent
## null-instance crash the first time that node is touched later on.
func _assert_required_nodes() -> void:
	var required := {
		"%ModelSprite": model_sprite,
		"%FaceLabel": face_label,
		"%ModelHolder": model_holder,
	}
	for path in required.keys():
		assert(required[path] != null, "CharacterPortrait: required node missing — " + path + ". Check 'Access as Unique Name' is enabled for it in the scene.")

func _on_stats_changed(stats: Dictionary) -> void:
	var worst: float = stats.values().min()
	var state := State.CRITICAL
	if worst >= THRIVING_THRESHOLD:
		state = State.THRIVING
	elif worst >= STABLE_THRESHOLD:
		state = State.STABLE
	elif worst >= STRAINED_THRESHOLD:
		state = State.STRAINED
	_show_state(state)

func _on_mission_ended(success: bool, _summary: String) -> void:
	_show_state(State.SUCCESS if success else State.FAILED)

func _show_state(state: State) -> void:
	var anim_name: String = STATE_ANIM_NAMES[state]
	if model_sprite.sprite_frames.has_animation(anim_name):
		model_sprite.play(anim_name)
		model_sprite.visible = true
		face_label.visible = false
		_update_portrait(state, anim_name)
	else:
		model_sprite.visible = false
		face_label.visible = true
		face_label.text = STATE_EMOJI[state]
		if portrait_rect != null:
			portrait_rect.texture = null

## Shows a head-only crop of the first frame of the current state's
## animation in the small portrait box. Reuses the same PNGs, so no
## extra art is needed.
func _update_portrait(state: State, anim_name: String) -> void:
	if portrait_rect == null:
		return
	_last_state = state
	_last_anim = anim_name
	var frames := model_sprite.sprite_frames
	if frames.get_frame_count(anim_name) == 0:
		portrait_rect.texture = null
		return

	var crop: Vector3 = PORTRAIT_CROP_FAILED if state == State.FAILED else PORTRAIT_CROP_DEFAULT
	var box := portrait_rect.size
	var aspect := 1.0
	if box.x > 0.0 and box.y > 0.0:
		aspect = box.y / box.x
	var crop_w := crop.z
	var crop_h := crop_w * aspect
	var frame_index: int = min(PORTRAIT_FRAME, frames.get_frame_count(anim_name) - 1)
	var frame_tex: Texture2D = frames.get_frame_texture(anim_name, frame_index)
	# Keep the crop inside the art canvas.
	crop_h = min(crop_h, frame_tex.get_height() - crop.y)
	crop_w = crop_h / aspect

	var atlas := AtlasTexture.new()
	atlas.atlas = frame_tex
	atlas.region = Rect2(crop.x - crop_w / 2.0, crop.y, crop_w, crop_h)
	portrait_rect.texture = atlas
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_SCALE

## Re-crops when the portrait box is resized, so the crop always matches
## the box's shape.
func _on_portrait_resized() -> void:
	if _last_anim != "":
		_update_portrait(_last_state, _last_anim)
