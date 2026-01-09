extends Spatial
class_name Mannequiny
# Controls the animation tree's transitions for this animated character.
# Adapted for slide-x's animation system


enum States {IDLE, RUN, AIR, LAND}

onready var animation_tree: AnimationTree = $AnimationTree
onready var _playback: AnimationNodeStateMachinePlayback = animation_tree["parameters/playback"]

var move_direction: = Vector3.ZERO setget set_move_direction
var is_moving: = false setget set_is_moving


func _ready() -> void:
	animation_tree.active = true


func set_move_direction(direction: Vector3) -> void:
	move_direction = direction
	# Adjust blend position for slide-x's animation tree if it has blending
	if animation_tree.has("parameters/move_ground/blend_position"):
		animation_tree["parameters/move_ground/blend_position"] = direction.length()


func set_is_moving(value: bool) -> void:
	is_moving = value
	# Set conditions for animation tree if they exist
	if animation_tree.has("parameters/conditions/is_moving"):
		animation_tree["parameters/conditions/is_moving"] = value


func transition_to(state_id: int) -> void:
	match state_id:
		States.IDLE:
			_playback.travel("idle")
		States.LAND:
			# slide-x doesn't have a dedicated land animation, use idle
			_playback.travel("idle")
		States.RUN:
			# For slide-x, use 'run' animation when moving
			_playback.travel("run")
		States.AIR:
			# Use jump animation for air state
			_playback.travel("jumping")
		_:
			_playback.travel("idle")
