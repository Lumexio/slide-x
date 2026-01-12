tool
class_name Player
extends KinematicBody
# Helper class for the Player scene's scripts to be able to have access to the
# camera and its orientation.
# This is the refactored version using state machine pattern


onready var camera: CameraRig = $CameraRig
onready var skin: Mannequiny = $visuals
onready var state_machine: StateMachine = $StateMachine


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _get_configuration_warning() -> String:
	return "Missing camera node" if not camera else ""
