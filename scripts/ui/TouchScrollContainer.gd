class_name TouchScrollContainer
extends ScrollContainer

## Enables intuitive touch-drag and mouse-drag scrolling for mobile devices.
## When dragging beyond the threshold, it prevents accidental clicks on child buttons.

@export var enable_vertical_drag: bool = true
@export var enable_horizontal_drag: bool = false
@export var drag_threshold: float = 8.0

var _is_touching: bool = false
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_last_pos: Vector2 = Vector2.ZERO
var _has_dragged: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_is_touching = false
		_has_dragged = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var global_rect = get_global_rect()
		if event.pressed:
			if global_rect.has_point(event.global_position):
				_is_touching = true
				_has_dragged = false
				_touch_start_pos = event.global_position
				_touch_last_pos = event.global_position
		else:
			if _is_touching and _has_dragged:
				get_viewport().set_input_as_handled()
			_is_touching = false
			_has_dragged = false

	elif event is InputEventMouseMotion and _is_touching:
		var delta = event.global_position - _touch_last_pos
		_touch_last_pos = event.global_position

		if not _has_dragged and _touch_start_pos.distance_to(event.global_position) > drag_threshold:
			_has_dragged = true

		if _has_dragged:
			if enable_vertical_drag:
				scroll_vertical -= int(delta.y)
			if enable_horizontal_drag:
				scroll_horizontal -= int(delta.x)
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenTouch:
		var global_rect = get_global_rect()
		if event.pressed:
			if global_rect.has_point(event.position):
				_is_touching = true
				_has_dragged = false
				_touch_start_pos = event.position
				_touch_last_pos = event.position
		else:
			if _is_touching and _has_dragged:
				get_viewport().set_input_as_handled()
			_is_touching = false
			_has_dragged = false

	elif event is InputEventScreenDrag and _is_touching:
		if not _has_dragged and _touch_start_pos.distance_to(event.position) > drag_threshold:
			_has_dragged = true

		if _has_dragged:
			if enable_vertical_drag:
				scroll_vertical -= int(event.relative.y)
			if enable_horizontal_drag:
				scroll_horizontal -= int(event.relative.x)
			get_viewport().set_input_as_handled()
