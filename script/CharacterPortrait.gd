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

	model_sprite.position = model_holder.size / 2.0
	model_sprite.scale = Vector2(3, 3)
	StatsManager.stats_changed.connect(_on_stats_changed)
	StatsManager.mission_ended.connect(_on_mission_ended)
	_on_stats_changed(StatsManager.stats)

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
	else:
		model_sprite.visible = false
		face_label.visible = true
		face_label.text = STATE_EMOJI[state]
