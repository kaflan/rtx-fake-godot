@icon("res://addons/fake_rtx/icon_bounce.svg")
class_name FakeRtxBounce
extends OmniLight3D
## Bounce light for a moving light (a flashlight, a car's headlights, a
## lantern): every physics frame a few rays follow the source's beam, and this
## light is placed just off the surface they hit, tinted by that surface's
## colour (red brick throws warm light back, green paint throws green). It is
## eased over time so it never pops.
##
## Works in every renderer, including Compatibility (web, phones), where Godot
## has no global illumination at all. Follows Godot's "faking global
## illumination" advice: no shadows, no specular.
##
## Use: add as a child of anything, set `source` to your SpotLight3D.

## The light whose beam is followed. Its -Z axis is the beam direction.
@export var source: Light3D
## Rays per frame. One goes down the middle; the rest turn round the cone.
@export_range(1, 8) var rays := 3
## Share of the source's energy a white surface sends back.
@export_range(0.0, 2.0) var ratio := 0.6
## How far off the surface the bounce sits.
@export var lift := 0.45
## How quickly the bounce follows the beam (higher = snappier).
@export var ease_speed := 9.0
## Beam length when the source is not a SpotLight3D.
@export var reach := 15.0
## Which physics layers the rays hit.
@export_flags_3d_physics var collision_mask := 1
## Physics bodies the rays pass through (usually the player holding the light).
@export var exclude_bodies: Array[CollisionObject3D] = []

var _frame := 0
var _target_position := Vector3.ZERO
var _target_colour := Color(1.0, 1.0, 1.0)
var _target_energy := 0.0


func _ready() -> void:
	top_level = true
	shadow_enabled = false
	light_specular = 0.0
	light_energy = 0.0
	if omni_range == 5.0:
		omni_range = 4.2
	omni_attenuation = 1.15


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_frame += 1
	_trace()
	var blend := 1.0 - exp(-ease_speed * delta)
	if light_energy <= 0.001 and _target_energy > 0.0:
		global_position = _target_position
	else:
		global_position = global_position.lerp(_target_position, blend)
	light_color = light_color.lerp(_target_colour, blend)
	light_energy = lerpf(light_energy, _target_energy, blend)
	visible = light_energy > 0.004


func _trace() -> void:
	_target_energy = 0.0
	if source == null or not is_instance_valid(source) or not source.is_visible_in_tree() or source.light_energy <= 0.01:
		return
	var space := get_world_3d().direct_space_state
	var origin := source.global_position
	var basis := source.global_transform.basis
	var length := reach
	var cone := 30.0
	if source is SpotLight3D:
		length = (source as SpotLight3D).spot_range
		cone = (source as SpotLight3D).spot_angle
	var spread := tan(deg_to_rad(cone * 0.45))
	var excluded: Array[RID] = []
	for body in exclude_bodies:
		if is_instance_valid(body):
			excluded.append(body.get_rid())
	var sum_position := Vector3.ZERO
	var sum_colour := Color(0.0, 0.0, 0.0)
	var weight := 0.0
	for i in rays:
		var direction := -basis.z
		if i > 0:
			var angle := float(_frame) * 2.39996 + float(i) * TAU / float(maxi(rays - 1, 1))
			direction = (direction + (basis.x * cos(angle) + basis.y * sin(angle)) * spread).normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * length, collision_mask)
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var at: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var near := 1.0 - clampf(origin.distance_to(at) / length, 0.0, 1.0)
		var w := near * near
		sum_position += (at + normal * lift) * w
		sum_colour += FakeRtx.albedo_of(hit["collider"]) * w
		weight += w
	if weight <= 0.0001:
		return
	_target_position = sum_position / weight
	var bounced := sum_colour / weight
	var lit := Color(bounced.r * source.light_color.r, bounced.g * source.light_color.g, bounced.b * source.light_color.b)
	var parts := FakeRtx.split_colour(lit)
	_target_colour = parts[0]
	_target_energy = source.light_energy * ratio * float(parts[1]) * (weight / float(rays) + 0.35)
