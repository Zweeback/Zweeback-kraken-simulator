extends Node3D

const KrakenMotorClass = preload("res://scripts/motor/kraken_motor.gd")
const ContactPlannerClass = preload("res://scripts/motor/contact_planner.gd")

const TENTACLE_COUNT := 8
const SEGMENTS_PER_TENTACLE := 7
const MOVE_SPEED := 7.0
const BOOST_MULTIPLIER := 1.8
const CAMERA_DISTANCE := 9.0
const CAMERA_HEIGHT := 3.0
const GRAPPLE_ACCEL := 26.0
const GRAPPLE_MAX_SPEED := 18.0

var kraken: Node3D
var camera: Camera3D
var hud_depth: Label
var hud_speed: Label
var hud_mode: Label
var hud_contact: Label
var tentacle_segments: Array = []
var tentacle_bases: Array = []
var motor: RefCounted
var contact_planner: RefCounted
var velocity := Vector3.ZERO
var yaw := 0.0
var pitch := -0.18
var elapsed := 0.0
var capture_frames := -1
var capture_demo := false

func _ready() -> void:
	_build_world()
	_build_kraken()
	motor = KrakenMotorClass.new()
	motor.setup(TENTACLE_COUNT)
	contact_planner = ContactPlannerClass.new()
	contact_planner.setup(TENTACLE_COUNT)
	_build_camera()
	_build_hud()
	_ensure_input_map()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if OS.has_environment("KRAKEN_CAPTURE"):
		capture_demo = true
		capture_frames = 45

func _process(delta: float) -> void:
	elapsed += delta
	_update_player(delta)
	_update_tentacles(delta)
	_update_camera(delta)
	_update_hud()
	if capture_frames >= 0:
		capture_frames -= 1
		if capture_frames == 0:
			var image := get_viewport().get_texture().get_image()
			var output := ProjectSettings.globalize_path("res://kraken_render.png")
			var error := image.save_png(output)
			print("KRAKEN_CAPTURE_PATH=", output, " ERROR=", error)
			get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * 0.0025
		pitch = clamp(pitch - event.relative.y * 0.0025, -0.75, 0.35)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.075, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.32, 0.38)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.24, 0.30)
	env.fog_light_energy = 0.75
	env.fog_density = 0.018
	env.fog_height = 8.0
	env.fog_height_density = 0.08
	environment_node.environment = env
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -25.0, 0.0)
	sun.light_color = Color(0.58, 0.86, 0.95)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 7.0, 0.0)
	fill.light_color = Color(0.10, 0.62, 0.72)
	fill.light_energy = 4.0
	fill.omni_range = 28.0
	add_child(fill)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(110.0, 110.0)
	floor.mesh = floor_mesh
	floor.position.y = -8.0
	floor.material_override = _material(Color(0.055, 0.11, 0.105), 0.82, 0.0)
	add_child(floor)

	var floor_body := StaticBody3D.new()
	floor_body.name = "SeafloorCollision"
	floor_body.position = Vector3(0.0, -8.25, 0.0)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(110.0, 0.5, 110.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	add_child(floor_body)

	var surface := MeshInstance3D.new()
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(120.0, 120.0)
	surface.mesh = surface_mesh
	surface.position.y = 12.0
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.12, 0.48, 0.62, 0.24)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	water_mat.roughness = 0.14
	water_mat.metallic = 0.18
	water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.material_override = water_mat
	add_child(surface)

	_build_scale_props()

func _build_scale_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77331
	for i in 18:
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(0.7, 2.5)
		mesh.height = mesh.radius * rng.randf_range(1.1, 2.0)
		rock.mesh = mesh
		rock.scale = Vector3(rng.randf_range(0.8, 1.8), rng.randf_range(0.45, 1.1), rng.randf_range(0.8, 1.8))
		rock.position = Vector3(rng.randf_range(-35.0, 35.0), -7.2, rng.randf_range(-35.0, 35.0))
		rock.material_override = _material(Color(0.075, 0.12, 0.115), 0.92, 0.0)
		add_child(rock)

	for i in 6:
		_add_wrappable_pylon(Vector3(-14.0 + i * 5.5, -1.0, -22.0), 15.0, 0.75)

	# Close traversal geometry for grapple / wrap testing.
	_add_wrappable_pylon(Vector3(-3.2, -1.0, -7.2), 15.0, 0.65)
	_add_wrappable_pylon(Vector3(3.0, -0.5, -8.6), 16.0, 0.75)
	_add_wrappable_pylon(Vector3(0.0, 2.5, -11.5), 8.0, 0.55)

	var beam_body := StaticBody3D.new()
	beam_body.name = "TraversalBeam"
	beam_body.position = Vector3(0.0, 4.5, -9.0)
	beam_body.set_meta("wrap_radius", 0.55)
	var beam_mesh := MeshInstance3D.new()
	var beam_box := BoxMesh.new()
	beam_box.size = Vector3(8.5, 0.75, 0.75)
	beam_mesh.mesh = beam_box
	beam_mesh.material_override = _material(Color(0.19, 0.17, 0.13), 0.68, 0.04)
	beam_body.add_child(beam_mesh)
	var beam_collision := CollisionShape3D.new()
	var beam_shape := BoxShape3D.new()
	beam_shape.size = Vector3(8.5, 0.75, 0.75)
	beam_collision.shape = beam_shape
	beam_body.add_child(beam_collision)
	add_child(beam_body)

func _add_wrappable_pylon(position: Vector3, height: float, radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = "WrappablePylon"
	body.position = position
	body.set_meta("wrap_radius", radius)

	var pylon := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.82
	mesh.bottom_radius = radius
	mesh.height = height
	pylon.mesh = mesh
	pylon.material_override = _material(Color(0.18, 0.16, 0.12), 0.72, 0.05)
	body.add_child(pylon)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _build_kraken() -> void:
	kraken = Node3D.new()
	kraken.name = "Kraken"
	kraken.position = Vector3(0.0, 0.5, 0.0)
	add_child(kraken)

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 1.5
	body_mesh.height = 2.5
	body.mesh = body_mesh
	body.scale = Vector3(1.15, 1.0, 1.28)
	body.material_override = _material(Color(0.42, 0.10, 0.56), 0.24, 0.12)
	kraken.add_child(body)

	var mantle := MeshInstance3D.new()
	var mantle_mesh := SphereMesh.new()
	mantle_mesh.radius = 1.1
	mantle_mesh.height = 2.0
	mantle.mesh = mantle_mesh
	mantle.position = Vector3(0.0, 1.05, 0.15)
	mantle.scale = Vector3(0.9, 1.25, 0.95)
	mantle.material_override = _material(Color(0.52, 0.15, 0.66), 0.20, 0.10)
	kraken.add_child(mantle)

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.18
		eye_mesh.height = 0.36
		eye.mesh = eye_mesh
		eye.position = Vector3(0.55 * side, 0.55, -1.18)
		eye.material_override = _material(Color(0.88, 0.91, 0.72), 0.18, 0.0)
		kraken.add_child(eye)

		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.08
		pupil_mesh.height = 0.16
		pupil.mesh = pupil_mesh
		pupil.position = Vector3(0.55 * side, 0.55, -1.34)
		pupil.material_override = _material(Color(0.02, 0.015, 0.025), 0.1, 0.0)
		kraken.add_child(pupil)

	for t in TENTACLE_COUNT:
		var chain: Array = []
		var angle := TAU * float(t) / float(TENTACLE_COUNT)
		var parent := Node3D.new()
		parent.position = Vector3(cos(angle) * 0.75, -0.75, sin(angle) * 0.75)
		parent.rotation.y = -angle
		kraken.add_child(parent)
		tentacle_bases.append(parent)

		var current_parent := parent
		for s in SEGMENTS_PER_TENTACLE:
			var joint := Node3D.new()
			joint.position = Vector3(0.0, -0.54, -0.17)
			current_parent.add_child(joint)

			var segment := MeshInstance3D.new()
			var segment_mesh := CapsuleMesh.new()
			var taper := 1.0 - float(s) / float(SEGMENTS_PER_TENTACLE) * 0.62
			segment_mesh.radius = 0.22 * taper
			segment_mesh.height = 0.82
			segment.mesh = segment_mesh
			segment.rotation.x = deg_to_rad(17.0)
			segment.material_override = _material(Color(0.48, 0.11, 0.62), 0.28, 0.08)
			joint.add_child(segment)

			chain.append(joint)
			current_parent = joint
		tentacle_segments.append(chain)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 68.0
	camera.near = 0.08
	add_child(camera)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "KRAKEN // HARBOR TEST BASIN"
	title.position = Vector2(24, 20)
	title.add_theme_font_size_override("font_size", 18)
	layer.add_child(title)

	hud_depth = Label.new()
	hud_depth.position = Vector2(24, 50)
	hud_depth.add_theme_font_size_override("font_size", 14)
	layer.add_child(hud_depth)

	hud_speed = Label.new()
	hud_speed.position = Vector2(24, 72)
	hud_speed.add_theme_font_size_override("font_size", 14)
	layer.add_child(hud_speed)

	hud_mode = Label.new()
	hud_mode.position = Vector2(24, 94)
	hud_mode.add_theme_font_size_override("font_size", 14)
	layer.add_child(hud_mode)

	hud_contact = Label.new()
	hud_contact.position = Vector2(24, 116)
	hud_contact.add_theme_font_size_override("font_size", 14)
	layer.add_child(hud_contact)

	var controls := Label.new()
	controls.text = "WASD swim   SPACE/CTRL vertical   SHIFT boost   Q grapple   C ghost   E hunt   MOUSE look"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	controls.position = Vector2(-260, -42)
	controls.size = Vector2(520, 30)
	controls.modulate = Color(1, 1, 1, 0.70)
	layer.add_child(controls)

	var dot := Label.new()
	dot.text = "•"
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-5, -12)
	dot.add_theme_font_size_override("font_size", 18)
	dot.modulate = Color(1, 1, 1, 0.55)
	layer.add_child(dot)

func _update_player(delta: float) -> void:
	var local_input := Vector3.ZERO
	local_input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	local_input.z = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	local_input.y = Input.get_action_strength("ascend") - Input.get_action_strength("descend")

	var yaw_basis := Basis(Vector3.UP, yaw)
	var move := yaw_basis * Vector3(local_input.x, 0.0, local_input.z)
	move.y = local_input.y
	if move.length() > 1.0:
		move = move.normalized()

	var speed := MOVE_SPEED
	if Input.is_action_pressed("boost"):
		speed *= BOOST_MULTIPLIER

	var target_velocity := move * speed
	velocity = velocity.lerp(target_velocity, 1.0 - exp(-4.8 * delta))

	var grapple_active: bool = Input.is_action_pressed("grapple") or capture_demo
	if grapple_active and contact_planner.has_primary_contact():
		var pull_vector: Vector3 = contact_planner.get_primary_point() - kraken.global_position
		if pull_vector.length_squared() > 0.04:
			velocity += pull_vector.normalized() * GRAPPLE_ACCEL * delta
			if velocity.length() > GRAPPLE_MAX_SPEED:
				velocity = velocity.normalized() * GRAPPLE_MAX_SPEED

	kraken.position += velocity * delta
	kraken.position.y = clamp(kraken.position.y, -5.8, 9.0)

	if Vector2(velocity.x, velocity.z).length() > 0.35:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		kraken.rotation.y = lerp_angle(kraken.rotation.y, target_yaw, 1.0 - exp(-5.5 * delta))

	var bob := sin(elapsed * 1.7) * 0.035
	kraken.position.y += bob * delta

func _update_tentacles(delta: float) -> void:
	var local_velocity: Vector3 = kraken.global_transform.basis.inverse() * velocity
	var wants_hunt: bool = Input.is_action_pressed("hunt") or capture_demo
	var wants_ghost: bool = Input.is_action_pressed("ghost")
	var wants_grapple: bool = Input.is_action_pressed("grapple") or capture_demo
	var aim_direction: Vector3 = -camera.global_transform.basis.z.normalized()

	contact_planner.update(
		get_world_3d(),
		kraken.global_transform,
		tentacle_bases,
		aim_direction,
		wants_hunt or wants_ghost or wants_grapple
	)
	motor.apply_contacts(contact_planner.payload())
	motor.update(
		delta,
		local_velocity,
		MOVE_SPEED * BOOST_MULTIPLIER,
		wants_hunt,
		wants_ghost
	)
	for t in tentacle_segments.size():
		var chain: Array = tentacle_segments[t]
		for s in chain.size():
			var joint: Node3D = chain[s]
			var target_rotation: Vector3 = motor.sample_joint_rotation(t, s, chain.size())
			joint.rotation = joint.rotation.lerp(target_rotation, 0.22)

	_apply_tentacle_separation()

func _apply_tentacle_separation() -> void:
	const SAFE_DISTANCE: float = 0.34
	const HARD_DISTANCE: float = 0.16
	for arm_a in tentacle_segments.size():
		var chain_a: Array = tentacle_segments[arm_a]
		for arm_b in range(arm_a + 1, tentacle_segments.size()):
			var chain_b: Array = tentacle_segments[arm_b]
			var count: int = mini(chain_a.size(), chain_b.size())
			for segment_index in range(1, count):
				var joint_a: Node3D = chain_a[segment_index]
				var joint_b: Node3D = chain_b[segment_index]
				var distance: float = joint_a.global_position.distance_to(joint_b.global_position)
				if distance >= SAFE_DISTANCE:
					continue

				var severity: float = 1.0 - clampf(distance / SAFE_DISTANCE, 0.0, 1.0)
				var direction_sign: float = -1.0 if ((arm_a + arm_b) % 2 == 0) else 1.0
				var correction: float = direction_sign * severity * 0.055
				joint_a.rotation.z += correction
				joint_b.rotation.z -= correction

				if distance < HARD_DISTANCE:
					# Presentation-level escape hatch: aggressively separate distal chains
					# instead of allowing a visible knot to persist.
					var hard_push: float = direction_sign * 0.045
					joint_a.rotation.x += absf(hard_push)
					joint_b.rotation.x -= absf(hard_push)

func _update_camera(delta: float) -> void:
	var yaw_basis := Basis(Vector3.UP, yaw)
	var horizontal_back := yaw_basis * Vector3(0.0, 0.0, CAMERA_DISTANCE)
	var desired := kraken.global_position + horizontal_back + Vector3(0.0, CAMERA_HEIGHT + pitch * 4.0, 0.0)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-7.0 * delta))
	camera.look_at(kraken.global_position + Vector3(0.0, 0.45, 0.0), Vector3.UP)

func _update_hud() -> void:
	hud_depth.text = "DEPTH  %+.1f m" % (-kraken.position.y)
	hud_speed.text = "SPEED  %.1f m/s" % velocity.length()
	hud_mode.text = "MOTOR  " + motor.intent_name()
	hud_contact.text = "CONTACT  LOCK" if contact_planner.has_primary_contact() else "CONTACT  SCANNING"

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _ensure_input_map() -> void:
	_register_key("move_forward", KEY_W)
	_register_key("move_back", KEY_S)
	_register_key("move_left", KEY_A)
	_register_key("move_right", KEY_D)
	_register_key("ascend", KEY_SPACE)
	_register_key("descend", KEY_CTRL)
	_register_key("boost", KEY_SHIFT)
	_register_key("grapple", KEY_Q)
	_register_key("ghost", KEY_C)
	_register_key("hunt", KEY_E)

func _register_key(action: StringName, key: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)

