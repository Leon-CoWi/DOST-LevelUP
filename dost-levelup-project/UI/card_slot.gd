extends Panel

@onready var itemDisplay = $CenterContainer/Panel/itemDisplay
var name_tween: Tween = null
var _orig_item_pos: Vector2
@onready var cost_label = $Cost
var _is_selected: bool = false
var _is_playable: bool = false

signal slot_clicked(slot_index)

@export var slot_index: int = -1
@export var card_resource: Card = null
@export var is_player_card: bool = true

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	_orig_item_pos = itemDisplay.position
	
	if has_signal("mouse_entered"):
		connect("mouse_entered", Callable(self, "_on_mouse_entered"))
	if has_signal("mouse_exited"):
		connect("mouse_exited", Callable(self, "_on_mouse_exited"))
	
	if cost_label:
		cost_label.visible = false

func set_card(card: Card) -> void:
	card_resource = card
	update_visual()

func update_visual() -> void:
	if card_resource and card_resource.texture_face_up:
		itemDisplay.texture = card_resource.texture_face_up
		itemDisplay.visible = true
		if cost_label:
			cost_label.text = str(card_resource.cost)
	else:
		itemDisplay.visible = false

func _gui_input(event):
	if card_resource:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Only allow player to select their own cards
			if is_player_card:
				emit_signal("slot_clicked", slot_index)
				if _is_selected:
					set_selected(false)
					get_parent().get_parent().current_selected = -1
					get_parent().get_parent().current_selected_type = ""
				else:
					set_selected(true)
					get_parent().get_parent().current_selected_type = card_resource.type
					#set every other card slot to unselected?
					get_parent().get_parent().call_deferred("deselect_other_slots", slot_index)

func set_playable(enabled: bool) -> void:
	_is_playable = enabled
	if enabled:
		itemDisplay.modulate = Color(1, 1, 1, 1)
	else:
		itemDisplay.modulate = Color(0.6, 0.6, 0.6, 1)

func set_selected(selected: bool) -> void:
	_is_selected = selected
	
	if name_tween and name_tween.is_valid():
		name_tween.kill()
		name_tween = null
	
	if selected:
		itemDisplay.scale = Vector2(1.5, 1.5)
		itemDisplay.position = _orig_item_pos + Vector2(0, -8)
		name_tween = create_tween()
		name_tween.set_loops()
		name_tween.tween_property(itemDisplay, "modulate", Color(0.8, 0.9, 1, 1), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		name_tween.tween_property(itemDisplay, "modulate", Color(1, 1, 1, 1), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		itemDisplay.scale = Vector2(1.0, 1.0)
		itemDisplay.position = _orig_item_pos
		itemDisplay.modulate = Color(1, 1, 1, 1)

func _on_mouse_entered():
	if card_resource:
		if cost_label:
			cost_label.visible = true
		if _is_selected:
			return
		var t = create_tween()
		t.tween_property(itemDisplay, "scale", Vector2(1.5, 1.5), 0.12)
		t.tween_property(itemDisplay, "position", _orig_item_pos + Vector2(0, -8), 0.12)

func _on_mouse_exited():
	if card_resource:
		if cost_label:
			cost_label.visible = false
		if _is_selected:
			return
		var t = create_tween()
		t.tween_property(itemDisplay, "scale", Vector2(1.0, 1.0), 0.12)
		t.tween_property(itemDisplay, "position", _orig_item_pos, 0.12)
