@tool
@icon("res://addons/fake_rtx/icon_water.svg")
class_name FakeRtxWater
extends MeshInstance3D
## A puddle or pool: a flat quad with the Fake RTX water shader, which cuts its
## own ragged outline (different for every puddle), ripples, drips, shows the
## ground through the water and mirrors the room with screen-space ray marching.
## Place it just above the floor (about 2 mm). No collision is added.

const SHADER := preload("res://addons/fake_rtx/fake_rtx_water.gdshader")

@export var size := Vector2(2.0, 1.4):
	set(value):
		size = value
		_rebuild()
@export var deep_colour := Color(0.012, 0.022, 0.018):
	set(value):
		deep_colour = value
		_apply()
@export var murk_colour := Color(0.045, 0.06, 0.045):
	set(value):
		murk_colour = value
		_apply()
## Set false for a clean rectangle (a tank, a channel).
@export var ragged_edge := true:
	set(value):
		ragged_edge = value
		_apply()
@export_range(0.0, 2.0) var ripples := 1.0:
	set(value):
		ripples = value
		_apply()
@export_range(0.0, 2.0) var drips := 1.0:
	set(value):
		drips = value
		_apply()
@export_range(0.0, 2.0) var reflection := 1.0:
	set(value):
		reflection = value
		_apply()
## How much of the ground shows through.
@export_range(0.0, 1.0) var clarity := 0.9:
	set(value):
		clarity = value
		_apply()

var _material: ShaderMaterial


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	mesh = plane
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	material_override = _material
	_apply()


func _apply() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("deep_colour", deep_colour)
	_material.set_shader_parameter("murk_colour", murk_colour)
	_material.set_shader_parameter("shaped", ragged_edge)
	_material.set_shader_parameter("ripple_strength", 0.55 * ripples)
	_material.set_shader_parameter("drip_strength", drips)
	_material.set_shader_parameter("reflection_strength", reflection)
	_material.set_shader_parameter("clarity", clarity)
