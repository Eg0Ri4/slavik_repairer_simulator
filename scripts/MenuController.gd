## MenuController.gd
## Полноэкранное меню + кнопка "↩ MENU" в игре.
## Добавляется в ui_layer из Main._setup_menu().
class_name MenuController
extends CanvasLayer

signal game_started
signal returned_to_menu

var _menu_root     : Control
var _gameplay_root : Control

func _ready() -> void:
	layer = 2   # выше основного HUD (layer 1 по умолчанию)
	_build()

func show_gameplay_hud() -> void:
	_gameplay_root.visible = true

func _build() -> void:
	# ── Полноэкранный оверлей меню ────────────────────────────────────────
	_menu_root        = ColorRect.new()
	_menu_root.name   = "MenuRoot"
	_menu_root.color  = Color(0.04, 0.03, 0.02, 0.88)
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	# Заголовок
	var title := Label.new()
	title.text = "TRUST ME,\nI'M AN ENGINEER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Fix anything. Trust no one. Especially yourself."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	vbox.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(gap)

	var start_btn := _btn("▶   START GAME", Vector2(300, 60), 22)
	start_btn.pressed.connect(_on_start)
	vbox.add_child(start_btn)

	var quit_btn := _btn("✕   QUIT", Vector2(300, 48), 16)
	quit_btn.pressed.connect(get_tree().quit)
	vbox.add_child(quit_btn)

	# ── In-game HUD: только кнопка "↩ MENU" в правом верхнем углу ────────
	_gameplay_root              = Control.new()
	_gameplay_root.name         = "GameplayRoot"
	_gameplay_root.visible      = false
	_gameplay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_gameplay_root)

	var back_btn            := _btn("↩  MENU", Vector2(120, 36), 13)
	back_btn.anchor_left    = 1.0
	back_btn.anchor_right   = 1.0
	back_btn.anchor_top     = 0.0
	back_btn.anchor_bottom  = 0.0
	back_btn.offset_left    = -132.0
	back_btn.offset_right   = -10.0
	back_btn.offset_top     = 10.0
	back_btn.offset_bottom  = 46.0
	back_btn.mouse_filter   = Control.MOUSE_FILTER_STOP
	back_btn.pressed.connect(_on_back)
	_gameplay_root.add_child(back_btn)

func _on_start() -> void:
	GameState.set_phase(GameState.GamePhase.PLAYING)
	_menu_root.visible     = false
	_gameplay_root.visible = false   # покажется после tween через show_gameplay_hud()
	game_started.emit()

func _on_back() -> void:
	GameState.set_phase(GameState.GamePhase.MENU)
	_gameplay_root.visible = false
	_menu_root.visible     = true
	returned_to_menu.emit()

func _btn(txt: String, min_size: Vector2, fsize: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", Color(0.96, 0.91, 0.76))
	for pair in [
		["normal",  Color(0.10, 0.08, 0.05, 0.93), Color(0.55, 0.45, 0.25)],
		["hover",   Color(0.30, 0.23, 0.12, 0.96), Color(1.00, 0.85, 0.30)],
		["pressed", Color(0.15, 0.12, 0.07, 0.96), Color(1.00, 1.00, 0.20)],
	]:
		var s := StyleBoxFlat.new()
		s.bg_color     = pair[1]
		s.border_color = pair[2]
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		s.content_margin_left   = 14
		s.content_margin_right  = 14
		s.content_margin_top    = 8
		s.content_margin_bottom = 8
		b.add_theme_stylebox_override(pair[0], s)
	return b
