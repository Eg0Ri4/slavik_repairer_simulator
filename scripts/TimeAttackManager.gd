## TimeAttackManager.gd
## Self-contained 5-Minute Time Attack mode manager.
##
## SETUP (add these 4 lines to Main.gd's _ready(), after _setup_new_hud()):
##
##   var _time_attack: TimeAttackManager = TimeAttackManager.new()
##   _time_attack.name = "TimeAttackManager"
##   add_child(_time_attack)
##   _time_attack.start()
##
## HOOK 1 – call this from Main._on_trust_me_pressed(), just before the early-returns:
##   _time_attack.on_evaluation_submitted(blueprint_evaluator, ghost_root)
##
## HOOK 2 – call this from Main._on_reset_pressed(), at the very end of the function:
##   _time_attack.on_clear_pressed()
##
## That's it. The manager listens to its own signals to drive the HUD overlay it builds.

class_name TimeAttackManager
extends Node

# ── Constants ────────────────────────────────────────────────────────────────
const TOTAL_TIME: float   = 600.0          # 10 minutes in seconds
const MIN_REQS:   int     = 2              # minimum requirements per order
const MAX_REQS:   int     = 4              # maximum requirements per order

## All tags the random order generator may choose from.
const ALL_TAGS: Array[String] = [
	"blade", "motor", "frame", "wheel", "pipe",
	"gear", "axle", "spring", "valve", "fan",
	"arm",   "leg",  "sensor", "tank",  "core"
]

## Friendly display names paired to tags (for client-readable descriptions).
const TAG_DISPLAY: Dictionary = {
	"blade":  "a spinning blade",
	"motor":  "a power motor",
	"frame":  "a structural frame",
	"wheel":  "a wheel",
	"pipe":   "a pipe section",
	"gear":   "a gear",
	"axle":   "an axle",
	"spring": "a spring",
	"valve":  "a valve",
	"fan":    "a cooling fan",
	"arm":    "an arm piece",
	"leg":    "a leg piece",
	"sensor": "a sensor",
	"tank":   "a tank",
	"core":   "a core piece"
}

## Toy names paired to primary tag (used for order titles).
const TOY_BLUEPRINTS: Array[Dictionary] = [
	{ "name": "Workshop Fan",       "primary": "blade"  },
	{ "name": "Go-Kart Engine",     "primary": "motor"  },
	{ "name": "Water Pump",         "primary": "valve"  },
	{ "name": "Robot Arm",          "primary": "arm"    },
	{ "name": "Gear Box",           "primary": "gear"   },
	{ "name": "Cooling Unit",       "primary": "fan"    },
	{ "name": "Mystery Machine",    "primary": "core"   },
	{ "name": "Pipe Assembly",      "primary": "pipe"   },
	{ "name": "Sensor Array",       "primary": "sensor" },
	{ "name": "Cart Chassis",       "primary": "frame"  },
]

# ── Signals ──────────────────────────────────────────────────────────────────

## Fired with the freshly-generated OrderData whenever a new random order is ready.
## Main.gd should store it in _order and call _populate_order_ui(order).
signal order_generated(order: OrderData)

## Fired every second with (seconds_left, total_score, orders_completed).
signal hud_updated(seconds_left: int, total_score: int, orders_completed: int)

## Fired when the timer reaches zero.
signal time_up(total_score: int, orders_completed: int)

# ── State ────────────────────────────────────────────────────────────────────
var _time_left:         float = TOTAL_TIME
var _orders_completed:  int   = 0
var _last_eval_pct:     int   = 0     # percentage from most recent evaluation
var _last_parts_used:   int   = 0     # parts used in the most recent evaluation
var _running:           bool  = false
var _input_blocked:     bool  = false

## TRUE only after TRUST ME was pressed for the current order.
## Prevents skipped/cleared orders from being counted.
var _submitted_this_order: bool = false

## Running totals for the end-screen summary.
var _total_parts_used:   int   = 0   # sum of parts placed across all submitted orders
var _pct_history:  Array[int]  = []  # final_pct for each submitted order

# ── Internal UI (built by this manager; no Main.gd edits needed for the panel) ─
var _hud_panel:       Panel  = null
var _timer_label:     Label  = null
var _orders_label:    Label  = null
var _time_up_overlay: Control = null

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_hud_panel()

func _process(delta: float) -> void:
	if not _running:
		return

	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_running = false
		_on_time_up()
		return

	_refresh_hud_labels()

# ── Public API ───────────────────────────────────────────────────────────────

## Start (or restart) the time-attack mode.
func start() -> void:
	_time_left        = TOTAL_TIME
	_orders_completed = 0
	_last_eval_pct         = 0
	_last_parts_used       = 0
	_submitted_this_order  = false
	_total_parts_used      = 0
	_pct_history           = []
	_running               = true
	_input_blocked         = false

	if _hud_panel:
		_hud_panel.visible = true
	if _time_up_overlay:
		_time_up_overlay.visible = false

	_refresh_hud_labels()
	_emit_new_order()

func set_paused(p: bool) -> void:
	if _time_left > 0.0:
		_running = not p

## Call this from Main._on_trust_me_pressed(), BEFORE its early-returns.
## Pass blueprint_evaluator, ghost_root, and assembly_pivot so we can score + count parts.
## The score is STORED here but NOT banked until _on_clear_pressed() (i.e. CLEAR ASSEMBLY).
func on_evaluation_submitted(bp_evaluator, ghost_root: Node3D) -> void:
	if not _running:
		return

	# Mark that TRUST ME was pressed for this order — skip won't count it.
	_submitted_this_order = true

	var pivot: Node3D = get_parent().get_node_or_null("AssemblyPivot")
	if ghost_root != null and bp_evaluator != null:
		var bp_result: Dictionary = bp_evaluator.evaluate(pivot)
		var spill_ratio: float    = bp_result.get("spill_ratio", 0.0)
		var base_pct: int         = bp_result.get("percentage", 0)
		var final_pct: int        = max(0, base_pct - int(spill_ratio * 100.0))
		_last_eval_pct            = final_pct
		_last_parts_used = bp_result.get("parts_used", 0)
	else:
		_last_eval_pct   = 0
		_last_parts_used = 0

## Call this from Main._on_reset_pressed(), at the very end of that function.
## Banks score and stats ONLY if TRUST ME was pressed for this order.
## Skipped orders (cleared without submitting) are silently discarded.
func on_clear_pressed() -> void:
	if not _running:
		return

	if _submitted_this_order:
		_orders_completed += 1
		_pct_history.append(_last_eval_pct)
		_total_parts_used += _last_parts_used

	# Always reset per-order state regardless of whether it was submitted.
	_submitted_this_order = false
	_last_eval_pct        = 0
	_last_parts_used      = 0
	_refresh_hud_labels()
	_emit_new_order()

## Returns a freshly-generated random OrderData. You can call this any time;
## it's also called internally when a new order is needed.
func generate_random_order() -> OrderData:
	var order := OrderData.new()

	# Pick a random toy blueprint for the title
	var toy: Dictionary = TOY_BLUEPRINTS[randi() % TOY_BLUEPRINTS.size()]
	order.toy_name          = "Broken " + toy["name"]
	order.pass_tolerance    = 40.0
	order.tolerance         = 0.5

	order.requirements = []
	order.required_component_tags = []

	order.client_description = "We need a working %s, fast!\nPlease assemble it according to the blueprint." % toy["name"]

	return order

# ── Private helpers ───────────────────────────────────────────────────────────

func _emit_new_order() -> void:
	var order: OrderData = generate_random_order()
	order_generated.emit(order)


func _refresh_hud_labels() -> void:
	var mins:  int = int(_time_left) / 60
	var secs:  int = int(_time_left) % 60
	var urgent: bool = _time_left <= 30.0

	if _timer_label:
		_timer_label.text = "%02d:%02d" % [mins, secs]
		_timer_label.modulate = Color(1.0, 0.25, 0.15) if urgent else Color(1.0, 0.9, 0.3)

	if _orders_label:
		_orders_label.text = "Orders: %d" % _orders_completed

	hud_updated.emit(int(_time_left), 0, _orders_completed)

func _on_time_up() -> void:
	_input_blocked = true
	_refresh_hud_labels()
	_show_time_up_overlay()
	time_up.emit(0, _orders_completed)

# ── HUD Construction ──────────────────────────────────────────────────────────

func _build_hud_panel() -> void:
	# Find the CanvasLayer that Main already created (named "UI").
	var canvas: CanvasLayer = _find_canvas_layer()
	if canvas == null:
		# Fallback: create our own CanvasLayer above everything else.
		canvas = CanvasLayer.new()
		canvas.name  = "TimeAttackUI"
		canvas.layer = 5
		add_child(canvas)

	# ── Top-right HUD strip ───────────────────────────────────────────────────
	_hud_panel = _make_styled_panel()
	_hud_panel.name                = "TimeAttackHUD"
	_hud_panel.custom_minimum_size = Vector2(230, 80)

	# Anchor top-right
	_hud_panel.set_anchor(SIDE_LEFT,   1.0)
	_hud_panel.set_anchor(SIDE_TOP,    0.0)
	_hud_panel.set_anchor(SIDE_RIGHT,  1.0)
	_hud_panel.set_anchor(SIDE_BOTTOM, 0.0)
	_hud_panel.offset_left   = -240.0
	_hud_panel.offset_top    = 10.0
	_hud_panel.offset_right  = -10.0
	_hud_panel.offset_bottom = 90.0

	canvas.add_child(_hud_panel)

	# Mode badge
	var mode_label := Label.new()
	mode_label.text     = "⏱ 10-MINUTE TIME ATTACK"
	mode_label.add_theme_font_size_override("font_size", 11)
	mode_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	mode_label.position = Vector2(8, 6)
	_hud_panel.add_child(mode_label)

	# Timer (large, center of panel)
	_timer_label = Label.new()
	_timer_label.text     = "10:00"
	_timer_label.add_theme_font_size_override("font_size", 28)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_timer_label.position = Vector2(8, 22)
	_hud_panel.add_child(_timer_label)



	# Orders counter
	_orders_label = Label.new()
	_orders_label.text     = "Orders: 0"
	_orders_label.add_theme_font_size_override("font_size", 14)
	_orders_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_orders_label.position = Vector2(100, 28)
	_hud_panel.add_child(_orders_label)

	_hud_panel.visible = false   # shown only once start() is called

	# ── TIME'S UP overlay (full screen, built now, shown on game end) ─────────
	_time_up_overlay = Control.new()
	_time_up_overlay.name = "TimeUpOverlay"
	_time_up_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_time_up_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_time_up_overlay.visible = false
	canvas.add_child(_time_up_overlay)

	# Semi-opaque dark backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.03, 0.02, 0.88)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_time_up_overlay.add_child(backdrop)

	# Centered card
	var card := _make_styled_panel()
	card.custom_minimum_size = Vector2(460, 320)
	card.set_anchor(SIDE_LEFT,   0.5)
	card.set_anchor(SIDE_TOP,    0.5)
	card.set_anchor(SIDE_RIGHT,  0.5)
	card.set_anchor(SIDE_BOTTOM, 0.5)
	card.offset_left   = -230.0
	card.offset_top    = -160.0
	card.offset_right  =  230.0
	card.offset_bottom =  160.0
	_time_up_overlay.add_child(card)

	var title_lbl := Label.new()
	title_lbl.text      = "⏰  TIME'S UP!"
	title_lbl.add_theme_font_size_override("font_size", 38)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	title_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_lbl.offset_top = 24.0
	title_lbl.offset_left = -200.0
	title_lbl.offset_right = 200.0
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.name   = "SubtitleLabel"
	subtitle_lbl.text   = "Orders completed: 0"
	subtitle_lbl.add_theme_font_size_override("font_size", 20)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	subtitle_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	subtitle_lbl.offset_top = -30.0
	subtitle_lbl.offset_left = -200.0
	subtitle_lbl.offset_right = 200.0
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(subtitle_lbl)

	var stats_lbl := Label.new()
	stats_lbl.name   = "StatsLabel"
	stats_lbl.text   = ""
	stats_lbl.add_theme_font_size_override("font_size", 15)
	stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.75))
	stats_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	stats_lbl.offset_top  = 36.0
	stats_lbl.offset_bottom = 72.0
	stats_lbl.offset_left = -200.0
	stats_lbl.offset_right = 200.0
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(stats_lbl)

	var grade_lbl := Label.new()
	grade_lbl.name   = "GradeLabel"
	grade_lbl.text   = ""
	grade_lbl.add_theme_font_size_override("font_size", 16)
	grade_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	grade_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grade_lbl.offset_top    = -52.0
	grade_lbl.offset_bottom = -28.0
	grade_lbl.offset_left   = -200.0
	grade_lbl.offset_right  =  200.0
	grade_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(grade_lbl)

	# Restart button
	var restart_btn := _make_styled_button("🔁  PLAY AGAIN")
	restart_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	restart_btn.offset_top    = -30.0
	restart_btn.offset_bottom =  -6.0
	restart_btn.offset_left   = -110.0
	restart_btn.offset_right  =  110.0
	restart_btn.add_theme_font_size_override("font_size", 16)
	restart_btn.pressed.connect(_on_restart_pressed)
	card.add_child(restart_btn)

func _show_time_up_overlay() -> void:
	if _time_up_overlay == null:
		return

	# Compute average similarity pct across submitted orders.
	var avg_pct: float = 0.0
	if _pct_history.size() > 0:
		var sum: int = 0
		for p in _pct_history:
			sum += p
		avg_pct = float(sum) / float(_pct_history.size())

	# Main stats block.
	var sub: Label = _time_up_overlay.find_child("SubtitleLabel", true, false)
	if sub:
		sub.text = "Orders completed: %d" % _orders_completed

	# Extra stats: parts used + average match %.
	var stats_lbl: Label = _time_up_overlay.find_child("StatsLabel", true, false)
	if stats_lbl:
		var avg_str: String = "—" if _pct_history.is_empty() else ("%d%%" % int(avg_pct))
		stats_lbl.text = "Parts used: %d  •  Average match: %s" % [_total_parts_used, avg_str]

	var grade_lbl: Label = _time_up_overlay.find_child("GradeLabel", true, false)
	if grade_lbl:
		grade_lbl.text = ""

	_time_up_overlay.visible = true

func _on_restart_pressed() -> void:
	if _time_up_overlay:
		_time_up_overlay.visible = false
	
	if get_parent() and get_parent().has_method("_on_skip_pressed"):
		get_parent()._on_skip_pressed()
		
	start()
	# start() already calls _emit_new_order() — no need to call it twice.

func _find_canvas_layer() -> CanvasLayer:
	# Walk up to Main and look for its "UI" CanvasLayer
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is CanvasLayer and child.name == "UI":
			return child as CanvasLayer
	return null

# ── UI Factory helpers ────────────────────────────────────────────────────────

func _make_styled_panel() -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color           = Color(0.07, 0.06, 0.05, 0.92)
	style.border_color       = Color(0.55, 0.45, 0.2, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_styled_button(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.22, 0.17, 0.10, 0.95)
	sn.border_color = Color(0.6, 0.5, 0.25)
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.38, 0.30, 0.14, 0.95)
	sh.border_color = Color(0.9, 0.78, 0.3)
	sh.set_border_width_all(2)
	sh.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", sh)

	var sp := StyleBoxFlat.new()
	sp.bg_color = Color(0.16, 0.13, 0.08, 0.95)
	sp.border_color = Color(1.0, 0.95, 0.2)
	sp.set_border_width_all(2)
	sp.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", sp)

	return btn
