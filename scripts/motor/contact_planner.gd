extends RefCounted
class_name KrakenContactPlanner

class Contact:
	var active: bool = false
	var tentacle_index: int = -1
	var world_point: Vector3 = Vector3.ZERO
	var world_normal: Vector3 = Vector3.UP
	var local_from_base: Vector3 = Vector3.ZERO
	var distance: float = 0.0
	var collider_id: int = 0
	var kind: String = "surface"
	var wrap_radius: float = 0.0

const MAX_REACH: float = 7.5
const SWEEP_RADIUS: float = 0.34
const LANE_ANGLE: float = 0.13
const MIN_CONTACT_SEPARATION: float = 0.8

var contacts: Array = []
var primary_index: int = -1
var primary_point: Vector3 = Vector3.ZERO
var primary_normal: Vector3 = Vector3.UP

func setup(tentacle_count: int) -> void:
	contacts.clear()
	for index in tentacle_count:
		var contact := Contact.new()
		contact.tentacle_index = index
		contacts.append(contact)

func clear() -> void:
	primary_index = -1
	primary_point = Vector3.ZERO
	primary_normal = Vector3.UP
	for item in contacts:
		var contact: Contact = item
		contact.active = false
		contact.kind = "surface"
		contact.wrap_radius = 0.0

func update(
	world: World3D,
	body_transform: Transform3D,
	tentacle_bases: Array,
	desired_world_direction: Vector3,
	enabled: bool
) -> void:
	clear()
	if not enabled or world == null:
		return

	var direction: Vector3 = desired_world_direction.normalized()
	if direction.length_squared() < 0.01:
		direction = -body_transform.basis.z.normalized()

	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var reserved_points: Array[Vector3] = []

	for index in mini(tentacle_bases.size(), contacts.size()):
		var base_node: Node3D = tentacle_bases[index]
		if not is_instance_valid(base_node):
			continue

		var side: float = -1.0 if index % 2 == 0 else 1.0
		var ring: float = (float(index) / float(maxi(contacts.size(), 1))) * TAU
		var lane_direction: Vector3 = (
			direction
			+ body_transform.basis.x * side * LANE_ANGLE
			+ body_transform.basis.y * sin(ring) * 0.055
		).normalized()

		var origin: Vector3 = base_node.global_position
		var target: Vector3 = origin + lane_direction * MAX_REACH

		var sphere := SphereShape3D.new()
		sphere.radius = SWEEP_RADIUS
		var sweep := PhysicsShapeQueryParameters3D.new()
		sweep.shape = sphere
		sweep.transform = Transform3D(Basis.IDENTITY, origin)
		sweep.motion = target - origin
		sweep.collision_mask = 1
		sweep.collide_with_areas = false
		sweep.collide_with_bodies = true

		var motion_result: PackedFloat32Array = space.cast_motion(sweep)
		if motion_result.is_empty() or motion_result[0] >= 1.0:
			continue

		var safe_fraction: float = clampf(motion_result[0], 0.0, 1.0)
		var ray_end: Vector3 = origin.lerp(target, minf(1.0, safe_fraction + 0.08))
		var ray := PhysicsRayQueryParameters3D.create(origin, ray_end, 1)
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			continue

		var hit_point: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]
		var collider: Object = hit["collider"]

		var too_close: bool = false
		for used_point in reserved_points:
			if hit_point.distance_to(used_point) < MIN_CONTACT_SEPARATION:
				too_close = true
				break
		if too_close and not _is_wrappable(collider):
			continue

		var contact: Contact = contacts[index]
		contact.active = true
		contact.world_point = hit_point
		contact.world_normal = hit_normal
		contact.local_from_base = base_node.to_local(hit_point)
		contact.distance = origin.distance_to(hit_point)
		contact.collider_id = collider.get_instance_id()
		contact.kind = "wrap" if _is_wrappable(collider) else "surface"
		contact.wrap_radius = float(collider.get_meta("wrap_radius", 0.0))
		reserved_points.append(hit_point)

		if primary_index < 0 or contact.distance < contacts[primary_index].distance:
			primary_index = index
			primary_point = hit_point
			primary_normal = hit_normal

func has_primary_contact() -> bool:
	return primary_index >= 0

func get_primary_point() -> Vector3:
	return primary_point

func get_primary_normal() -> Vector3:
	return primary_normal

func payload() -> Array:
	var data: Array = []
	for item in contacts:
		var contact: Contact = item
		data.append({
			"active": contact.active,
			"tentacle_index": contact.tentacle_index,
			"world_point": contact.world_point,
			"world_normal": contact.world_normal,
			"local_from_base": contact.local_from_base,
			"distance": contact.distance,
			"kind": contact.kind,
			"wrap_radius": contact.wrap_radius,
		})
	return data

func _is_wrappable(collider: Object) -> bool:
	return collider != null and collider.has_meta("wrap_radius")
