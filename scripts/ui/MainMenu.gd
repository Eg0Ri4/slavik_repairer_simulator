extends CanvasLayer

@export var play_btn: Button
@export var exit_btn: Button

func _ready() -> void:
	if play_btn:
		play_btn.pressed.connect(_on_play_pressed)
	if exit_btn:
		exit_btn.pressed.connect(_on_exit_pressed)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
