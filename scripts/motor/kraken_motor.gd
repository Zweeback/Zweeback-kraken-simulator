extends RefCounted
class_name KrakenMotor

enum Intent {
	FLOW,
	HUNT,
	GHOST,
}

enum Role {
	STREAM,
	REACH,
	GRIP,
	WRAP,
	PULL,
	BRACE,
	PROBE,
	RECOVER,
}

class TentacleState:
	var role: int = Role.STREAM
	var phase_offset: float = 0.0
	var lane_bias: float = 0.0
	var stiffness: float = 0.25
	var extension: float = 0.5
	var contact_active: bool = false
	var contact_kind: String = "surface"
	var contact_distance: float = 0.0
	var target_local: Vector3 = Vector3.ZERO
	var wrap_radius: float = 0.0

var states: Array = []
var intent: int = Intent.FLOW
var clock: float = 0.0
var speed_ratio: float = 0.0
var move_local: Vector3 = Vector3.ZERO
var contact_payload: Array = []

func setup(tentacle_count: int) -> void:
	states.clear()
	for index in tentacle_count:
		var state := TentacleState.new()
		state.phase_offset = TAU * float(index) / float(maxi(tentacle_count, 1))
		state.lane_bias = -1.0 if index % 2 == 0 else 1.0
		states.append(state)

func update(delta: float, local_velocity: Vector3, max_speed: float, wants_hunt: bool, wants_ghost: bool) -> void:
	clock += delta
	move_local = local_velocity
	speed_ratio = clampf(local_velocity.length() / maxf(max_speed, 0.001), 0.0, 1.0)

	if wants_ghost:
		intent = Intent.GHOST
	elif wants_hunt:
		intent = Intent.HUNT
	else:
		intent = Intent.FLOW

	_assign_roles()

func apply_contacts(payload: Array) -> void:
	contact_payload = payload
	for index in states.size():
		var state: TentacleState = states[index]
		state.contact_active = false
		state.contact_kind = "surface"
		state.contact_distance = 0.0
		state.target_local = Vector3.ZERO
		state.wrap_radius = 0.0
		if index >= contact_payload.size():
			continue
		var data: Dictionary = contact_payload[index]
		if not bool(data.get("active", false)):
			continue
		state.contact_active = true
		state.contact_kind = String(data.get("kind", "surface"))
		state.contact_distance = float(data.get("distance", 0.0))
		state.target_local = Vector3(data.get("local_from_base", Vector3.ZERO))
		state.wrap_radius = float(data.get("wrap_radius", 0.0))

	_assign_roles()

func _assign_roles() -> void:
	for index in states.size():
		var state: TentacleState = states[index]
		match intent:
			Intent.FLOW:
				state.role = Role.STREAM
				state.stiffness = lerpf(0.22, 0.48, speed_ratio)
				state.extension = lerpf(0.48, 0.72, speed_ratio)
			Intent.GHOST:
				if index == 2 or index == 5:
					state.role = Role.PROBE
					state.stiffness = 0.42
					state.extension = 0.68
				else:
					state.role = Role.STREAM
					state.stiffness = 0.36
					state.extension = 0.58
			Intent.HUNT:
				if index == 0 or index == 1:
					state.role = Role.REACH
					state.stiffness = 0.58
					state.extension = 0.92
				elif index == 3 or index == 6:
					state.role = Role.BRACE
					state.stiffness = 0.82
					state.extension = 0.52
				else:
					state.role = Role.STREAM
					state.stiffness = 0.38
					state.extension = 0.62

		if state.contact_active:
			if state.contact_kind == "wrap" and state.contact_distance < 2.35:
				state.role = Role.WRAP
				state.stiffness = 0.68
				state.extension = 0.88
			elif state.contact_distance < 1.15:
				state.role = Role.GRIP
				state.stiffness = 0.62
				state.extension = 0.72
			else:
				state.role = Role.REACH
				state.stiffness = 0.55
				state.extension = 0.94

	var has_contact: bool = false
	for item in states:
		var contact_state: TentacleState = item
		if contact_state.contact_active:
			has_contact = true
			break
	if has_contact:
		for index in states.size():
			var support_state: TentacleState = states[index]
			if not support_state.contact_active and (index == 3 or index == 6):
				support_state.role = Role.BRACE
				support_state.stiffness = 0.84
				support_state.extension = 0.48

func sample_joint_rotation(tentacle_index: int, segment_index: int, segment_count: int) -> Vector3:
	if tentacle_index < 0 or tentacle_index >= states.size():
		return Vector3.ZERO

	var state: TentacleState = states[tentacle_index]
	var segment_t: float = float(segment_index) / float(maxi(segment_count - 1, 1))
	var wave: float = clock * (1.65 + 0.35 * speed_ratio) + state.phase_offset + segment_t * 2.5
	var separation: float = state.lane_bias * (1.0 - segment_t) * 0.055

	var target_side: float = 0.0
	var target_vertical: float = 0.0
	if state.contact_active and state.target_local.length_squared() > 0.001:
		var target_direction: Vector3 = state.target_local.normalized()
		var horizontal: float = sqrt(target_direction.x * target_direction.x + target_direction.z * target_direction.z)
		target_side = clampf(atan2(target_direction.x, -target_direction.z), -1.35, 1.35)
		target_vertical = clampf(atan2(target_direction.y, maxf(horizontal, 0.001)), -0.9, 0.9)

	match state.role:
		Role.REACH:
			var bend_front: float = clampf((clock * 1.8 + state.phase_offset * 0.15) - segment_t * 1.35, 0.0, 1.0)
			return Vector3(
				lerpf(0.08, -0.10, bend_front) - target_vertical * 0.13,
				0.0,
				separation - target_side * 0.12 + sin(wave * 0.55) * 0.025
			)
		Role.GRIP:
			var distal_curl: float = smoothstep(0.48, 1.0, segment_t)
			return Vector3(
				0.04 - target_vertical * 0.10 + distal_curl * 0.30,
				0.0,
				separation - target_side * 0.10 + sin(wave * 0.38) * 0.02
			)
		Role.BRACE:
			return Vector3(
				0.21 + sin(wave * 0.42) * 0.025,
				0.0,
				separation * 1.5
			)
		Role.PROBE:
			return Vector3(
				0.16 + sin(wave * 0.72) * 0.12,
				0.0,
				separation + cos(wave * 0.91) * (0.08 + segment_t * 0.07)
			)
		Role.WRAP:
			var wrap_progress: float = smoothstep(0.22, 1.0, segment_t)
			var helix: float = wave * 0.9 + segment_t * TAU * 1.25
			return Vector3(
				0.10 - target_vertical * 0.08 + sin(helix) * (0.08 + 0.18 * wrap_progress),
				0.0,
				separation - target_side * 0.08 + cos(helix) * (0.12 + 0.24 * wrap_progress)
			)
		_:
			var amplitude: float = lerpf(0.11, 0.055, speed_ratio)
			return Vector3(
				0.13 + sin(wave) * amplitude,
				0.0,
				separation + cos(wave * 0.83) * (amplitude * 0.85 + segment_t * 0.035)
			)

func intent_name() -> String:
	match intent:
		Intent.HUNT:
			return "HUNT"
		Intent.GHOST:
			return "GHOST"
		_:
			return "FLOW"
