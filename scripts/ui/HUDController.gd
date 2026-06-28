extends CanvasLayer
class_name HUDController

# ── Signals ─────────────────────────────────────────────────────────────────
signal submit_pressed()
signal clear_pressed()
signal skip_pressed()
signal menu_pressed()
signal tool_changed(new_tool)

# ── Enums ───────────────────────────────────────────────────────────────────
enum ToolState { HAND, TAPE, NAIL, CROWBAR }

# ── State ───────────────────────────────────────────────────────────────────
var current_tool: ToolState = ToolState.HAND

# ── Node References (Set via Inspector or %UniqueNames) ─────────────────────
@export var score_label: Label
@export var submit_btn: Button
@export var clear_btn: Button
@export var skip_btn: Button

@export var timer_label: Label
@export var money_label: Label
@export var menu_btn: Button

@export var holding_label: Label
@export var tools_container: HBoxContainer

@export var pause_menu: ColorRect
@export var resume_btn: Button
@export var quit_btn: Button

func _ready() -> void:
	# Connect UI Signals
	if submit_btn: submit_btn.pressed.connect(_on_submit_pressed)
	if clear_btn: clear_btn.pressed.connect(_on_clear_pressed)
	if skip_btn: skip_btn.pressed.connect(_on_skip_pressed)
	if menu_btn: menu_btn.pressed.connect(_on_menu_pressed)
	
	if resume_btn: resume_btn.pressed.connect(_on_resume_pressed)
	if quit_btn: quit_btn.pressed.connect(_on_quit_pressed)
	
	if tools_container:
		var index = 0
		for child in tools_container.get_children():
			if child is Button:
				var bound_index = index # local copy for lambda
				child.pressed.connect(func():
					_set_tool(bound_index as ToolState)
				)
				index += 1
	
	_update_holding_ui()

func _set_tool(state: ToolState) -> void:
	current_tool = state
	_update_holding_ui()
	tool_changed.emit(current_tool)

# ── Input Handling (Tool Switching) ──────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_1:
				_set_tool(ToolState.HAND)
				get_viewport().set_input_as_handled()
			KEY_2:
				_set_tool(ToolState.TAPE)
				get_viewport().set_input_as_handled()
			KEY_3:
				_set_tool(ToolState.NAIL)
				get_viewport().set_input_as_handled()
			KEY_4:
				_set_tool(ToolState.CROWBAR)
				get_viewport().set_input_as_handled()



# ── Public UI Update Methods ─────────────────────────────────────────────────
func update_score(val: float) -> void:
	if score_label:
		score_label.text = "Score: %d%%" % int(val)

func update_timer(time_str: String) -> void:
	if timer_label:
		timer_label.text = time_str

func update_money(val: int) -> void:
	if money_label:
		money_label.text = "$%d" % val

# ── Internal Helpers ─────────────────────────────────────────────────────────
func _update_holding_ui() -> void:
	if holding_label:
		match current_tool:
			ToolState.HAND:
				holding_label.text = "Holding: Nothing (Hand Mode)"
			ToolState.TAPE:
				holding_label.text = "Holding: Duct Tape"
			ToolState.NAIL:
				holding_label.text = "Holding: Nails"
			ToolState.CROWBAR:
				holding_label.text = "Holding: Crowbar"

# ── Button Callbacks ─────────────────────────────────────────────────────────
func _on_submit_pressed() -> void:
	submit_pressed.emit()

func _on_clear_pressed() -> void:
	clear_pressed.emit()

func _on_skip_pressed() -> void:
	skip_pressed.emit()

func _on_menu_pressed() -> void:
	if pause_menu:
		pause_menu.visible = true
	menu_pressed.emit()

func _on_resume_pressed() -> void:
	if pause_menu:
		pause_menu.visible = false

func _on_quit_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
