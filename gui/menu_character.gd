extends Spatial


onready var KineticChad=$"KineticChad"
onready var AkimboBoy=$"AkimboBoy"
onready var FairyFire=$"FairyFire"
var selection_tween = Tween.new()
var current_character = ""

const CHARACTER_ORDER = ["AkimboBoy", "KineticChad", "FairyFire"]
onready var CHARACTER_NODES = [AkimboBoy, KineticChad, FairyFire]
const CHARACTER_SPACING = 3.0
const CHARACTER_MOVE_TIME = 0.35

# Called when the node enters the scene tree for the first time.
func _ready():
	add_child(selection_tween)
	_select_character("AkimboBoy", false)
	


func _select_character(character_name, animate = true):
	current_character = character_name

	var selected_index = CHARACTER_ORDER.find(character_name)
	if selected_index == -1:
		return

	selection_tween.stop_all()
	selection_tween.remove_all()

	for index in range(CHARACTER_NODES.size()):
		var character = CHARACTER_NODES[index]
		var distance_from_selected = index - selected_index
		var target_x = distance_from_selected * CHARACTER_SPACING
		var target_translation = Vector3(target_x, character.translation.y, character.translation.z)

		if animate:
			selection_tween.interpolate_property(
				character,
				"translation",
				character.translation,
				target_translation,
				CHARACTER_MOVE_TIME,
				Tween.TRANS_QUAD,
				Tween.EASE_OUT
			)
		else:
			character.translation = target_translation

	if animate:
		selection_tween.start()


func _on_AkimboBoy_pressed():
	_select_character("AkimboBoy")

func _on_Kinetic_Chad_pressed():
	_select_character("KineticChad")

func _on_FairyFire_pressed():
	_select_character("FairyFire")


func _on__Back_pressed():
	var controller = GameGlobal.get_game_controller()
	if controller != null:
		controller.change_world3d_scene("res://gui/main_menu.tscn")

func _on_Start_Game_pressed():
	var controller = GameGlobal.get_game_controller()
	if controller != null:
		controller.change_world3d_scene("res://scenes/levels/level_1.tscn")
