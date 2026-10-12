class_name Hud
extends CanvasLayer
## On-screen UI for both views. Everything sits inside the SafeArea container.

signal view_toggle_pressed

@onready var joystick: TouchJoystick = $SafeArea/TouchJoystick
@onready var _view_button: Button = $SafeArea/ViewButton


func _ready() -> void:
	_view_button.pressed.connect(view_toggle_pressed.emit)


func set_view_button_text(text: String) -> void:
	_view_button.text = text
