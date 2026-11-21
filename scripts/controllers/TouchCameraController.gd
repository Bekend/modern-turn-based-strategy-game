class_name TouchCameraController
extends Camera2D

## Mobile-optimized 2D Camera handling single-finger drag pan,
## two-finger pinch-to-zoom, tap-to-select disambiguation, and desktop mouse fallback.

signal tile_tapped(grid_coords: Vector2i)

@export var tile_size: Vector2 = Vector2(16, 16)
@export var min_zoom: float = 0.8
@export var max_zoom: float = 3.5
@export var zoom_step: float = 0.15
@export var drag_damping: float = 0.90
@export var tap_threshold_px: float = 24.0

var map_bounds: Rect2 = Rect2(0, 0, 36 * 16, 24 * 16)

# Touch tracking state
var touches: Dictionary = {} # index -> Vector2
var initial_pinch_distance: float = 0.0
var initial_pinch_zoom: float = 1.0
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_start_time: float = 0.0
var has_dragged: bool = false
var pan_velocity: Vector2 = Vector2.ZERO

var is_mouse_dragging: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var mouse_press_pos: Vector2 = Vector2.ZERO
var mouse_press_time: float = 0.0
var last_tap_time: float = 0.0

func _ready() -> void:
	zoom = Vector2(1.5, 1.5)
	position = map_bounds.size * 0.5

func set_map_dimensions(width: int, height: int, cell_size: int = 16) -> void:
	tile_size = Vector2(cell_size, cell_size)
	var map_w_px = float(width * cell_size)
	var map_h_px = float(height * cell_size)
	map_bounds = Rect2(0, 0, map_w_px, map_h_px)

	var vp_size = get_viewport_rect().size
	# Calculate zoom required to fill viewport completely with zero empty borders
	var fill_x = vp_size.x / map_w_px
	var fill_y = vp_size.y / map_h_px
	min_zoom = maxf(fill_x, fill_y)
	max_zoom = maxf(min_zoom * 2.5, 4.0)

	var pad_bottom = int(135.0 / min_zoom)
	limit_left = 0
	limit_top = 0
	limit_right = int(map_w_px)
	limit_bottom = int(map_h_px + pad_bottom)

	_set_clamped_zoom(min_zoom * 1.15)
	_clamp_camera()

func focus_on_tile(coords: Vector2i) -> void:
	position = Vector2(coords.x * tile_size.x + tile_size.x * 0.5, coords.y * tile_size.y + tile_size.y * 0.5)
	_clamp_camera()

func _process(delta: float) -> void:
	# Inertia pan damping
	if touches.is_empty() and not is_mouse_dragging:
		if pan_velocity.length_squared() > 1.0:
			position += pan_velocity * delta
			pan_velocity *= pow(drag_damping, delta * 60.0)
			_clamp_camera()
		else:
			pan_velocity = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	# ---------------------------------------------------------
	# TOUCH EVENTS (MOBILE & TOUCH EMULATION)
	# ---------------------------------------------------------
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				touch_start_pos = event.position
				touch_start_time = Time.get_ticks_msec() / 1000.0
				has_dragged = false
				pan_velocity = Vector2.ZERO
			elif touches.size() == 2:
				var t_keys = touches.keys()
				initial_pinch_distance = touches[t_keys[0]].distance_to(touches[t_keys[1]])
				initial_pinch_zoom = zoom.x
				has_dragged = true
		else:
			var lifted_index = event.index
			if touches.size() == 1 and not has_dragged:
				var dist = event.position.distance_to(touch_start_pos)
				if dist <= tap_threshold_px:
					_handle_tap(event.position)

			touches.erase(lifted_index)
			if touches.is_empty():
				initial_pinch_distance = 0.0

	elif event is InputEventScreenDrag:
		touches[event.index] = event.position

		if touches.size() == 1:
			var move_dist = event.position.distance_to(touch_start_pos)
			if move_dist > tap_threshold_px:
				has_dragged = true

			if has_dragged:
				var move_delta = event.relative / zoom.x
				position -= move_delta
				pan_velocity = -event.velocity / zoom.x
				_clamp_camera()

		elif touches.size() >= 2:
			has_dragged = true
			var t_keys = touches.keys()
			var p1: Vector2 = touches[t_keys[0]]
			var p2: Vector2 = touches[t_keys[1]]
			var curr_dist = p1.distance_to(p2)

			if initial_pinch_distance > 5.0 and curr_dist > 5.0:
				var target_zoom = (curr_dist / initial_pinch_distance) * initial_pinch_zoom
				_set_clamped_zoom(target_zoom)

	# ---------------------------------------------------------
	# DESKTOP MOUSE FALLBACK (Scroll zoom, Left click tap, Right drag)
	# ---------------------------------------------------------
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_clamped_zoom(zoom.x + zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_clamped_zoom(zoom.x - zoom_step)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				mouse_press_pos = event.position
				mouse_press_time = Time.get_ticks_msec() / 1000.0
			else:
				var dist = event.position.distance_to(mouse_press_pos)
				if dist <= tap_threshold_px:
					_handle_tap(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_mouse_dragging = true
				last_mouse_pos = event.position
			else:
				is_mouse_dragging = false

	elif event is InputEventMouseMotion:
		if is_mouse_dragging:
			var diff = (event.position - last_mouse_pos) / zoom.x
			position -= diff
			last_mouse_pos = event.position
			_clamp_camera()

func _set_clamped_zoom(z_val: float) -> void:
	var clamped = clampf(z_val, min_zoom, max_zoom)
	zoom = Vector2(clamped, clamped)
	_clamp_camera()

func _clamp_camera() -> void:
	var half_screen = (get_viewport_rect().size * 0.5) / zoom.x
	if (limit_right - limit_left) <= half_screen.x * 2.0:
		position.x = (limit_left + limit_right) * 0.5
	else:
		position.x = clampf(position.x, limit_left + half_screen.x, limit_right - half_screen.x)

	if (limit_bottom - limit_top) <= half_screen.y * 2.0:
		position.y = (limit_top + limit_bottom) * 0.5
	else:
		position.y = clampf(position.y, limit_top + half_screen.y, limit_bottom - half_screen.y)

func _handle_tap(screen_pos: Vector2) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - last_tap_time < 0.08:
		return
	last_tap_time = now

	var canvas_xform = get_canvas_transform()
	var world_pos = canvas_xform.affine_inverse() * screen_pos
	var tile_coord = Vector2i(floori(world_pos.x / tile_size.x), floori(world_pos.y / tile_size.y))
	tile_tapped.emit(tile_coord)

