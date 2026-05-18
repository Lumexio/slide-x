extends Node2D




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_Start_pressed() -> void:
	var _change_err = get_tree().change_scene("res://Main menu/Menu_character.tscn")


func _on_Quit_pressed() -> void:
	get_tree().quit()
