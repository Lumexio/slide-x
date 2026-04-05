extends Spatial


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_Control_pressed():
	get_tree().change_scene("res://scenes/levels/level_1.tscn")





func _on_Kinetic_Chad_pressed():
	get_tree().change_scene("res://scenes/levels/level_1.tscn")


func _on__Back_pressed():
	get_tree().change_scene("res://gui/main_menu.tscn")
