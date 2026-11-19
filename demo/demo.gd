extends Node3D
## Fake RTX demo: a dark room with coloured walls, a flashlight you aim with
## the mouse, a bounce light following its beam, and two puddles.
## Hold B to compare with the bounce switched off.

var camera: Camera3D
var torch: SpotLight3D
var bounce: FakeRtxBounce
var _yaw := 0.0
var _pitch := -0.25


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.05, 0.05, 0.06)
	add_child(env)

	_box(Vector3(0, -0.05, 0), Vector3(10, 0.1, 10), Color(0.32, 0.32, 0.30))
	_box(Vector3(0, 3.05, 0), Vector3(10, 0.1, 10), Color(0.25, 0.25, 0.25))
	_box(Vector3(0, 1.5, -5), Vector3(10, 3, 0.1), Color(0.62, 0.20, 0.12))
	_box(Vector3(-5, 1.5, 0), Vector3(0.1, 3, 10), Color(0.15, 0.48, 0.22))
	_box(Vector3(5, 1.5, 0), Vector3(0.1, 3, 10), Color(0.16, 0.24, 0.60))
	_box(Vector3(0, 1.5, 5), Vector3(10, 3, 0.1), Color(0.55, 0.55, 0.50))
	_box(Vector3(1.2, 0.5, -2.2), Vector3(1, 1, 1), Color(0.85, 0.80, 0.70))

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-2.5, 2.7, -2.5)
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 1.2
	lamp.omni_range = 4.5
	add_child(lamp)

	var puddle := FakeRtxWater.new()
	puddle.size = Vector2(2.6, 1.8)
	puddle.position = Vector3(-0.6, 0.002, -1.4)
	add_child(puddle)
	var pool := FakeRtxWater.new()
	pool.size = Vector2(1.6, 1.2)
	pool.position = Vector3(2.4, 0.002, 1.0)
	pool.rotation_degrees.y = 25.0
	add_child(pool)

	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 3.2)
	add_child(camera)
	torch = SpotLight3D.new()
	torch.position = Vector3(0.2, -0.2, -0.1)
	torch.light_energy = 2.6
	torch.spot_range = 16.0
	torch.spot_angle = 38.0
	torch.shadow_enabled = true
	camera.add_child(torch)

	bounce = FakeRtxBounce.new()
	bounce.source = torch
	add_child(bounce)

	var help := Label.new()
	help.text = "Mouse — aim the torch   ·   hold B — bounce off"
	help.position = Vector2(16, 12)
	var layer := CanvasLayer.new()
	layer.add_child(help)
	add_child(layer)
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * 0.004
		_pitch = clampf(_pitch - event.relative.y * 0.004, -1.2, 1.0)
		_apply_view()
	if event is InputEventKey and event.keycode == KEY_B:
		bounce.ratio = 0.0 if event.pressed else 0.6


func _apply_view() -> void:
	camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _box(pos: Vector3, size: Vector3, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
