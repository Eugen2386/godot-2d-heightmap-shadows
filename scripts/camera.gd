extends Camera2D

@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var zoom_step: float = 0.1
@export var zoom_smoothness: float = 10.0

var _target_zoom: float = 1.0
var _is_panning: bool = false


func _ready() -> void:
	_target_zoom = zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
				
	if event is InputEventMouseMotion and _is_panning:
		position -= event.relative / zoom


func _process(delta: float) -> void:
	var new_zoom = lerpf(zoom.x, _target_zoom, zoom_smoothness * delta)
	zoom = Vector2(new_zoom, new_zoom)
