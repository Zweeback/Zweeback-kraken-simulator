extends Node3D

const KrakenMotorClass = preload("res://scripts/motor/kraken_motor.gd")
const ContactPlannerClass = preload("res://scripts/motor/contact_planner.gd")
const TentacleTubeClass = preload("res://scripts/visual/tentacle_tube.gd")

const TENTACLE_COUNT := 8
const SEGMENTS_PER_TENTACLE := 11
const MOVE_SPEED := 7.0
const BOOST_MULTIPLIER := 1.8
const CAMERA_DISTANCE := 6.2
const CAMERA_HEIGHT := 2.0
const GRAPPLE_ACCEL := 26.0
const GRAPPLE_MAX_SPEED := 18.0
const GRAPPLE_ORBIT_RADIUS := 2.45

var kraken: Node3D
var camera: Camera3D
var hud_depth: Label
var hud_speed: Label
var hud_mode: Label
var hud_contact: Label
var controls_label: Label
var tentacle_segments: Array = []
var tentacle_visuals: Array = []
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
	env.background_color = Color(0.006, 0.028, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.055, 0.19, 0.25)
	env.ambient_light_energy = 0.72
	env.fog_enabled = true
	env.fog_light_color = Color(0.025, 0.16, 0.22)
	env.fog_light_energy = 0.95
	env.fog_density = 0.026
	env.fog_height = 8.0
	env.fog_height_density = 0.08
	environment_node.environment = env
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -25.0, 0.0)
	sun.light_color = Color(0.40, 0.76, 0.92)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 5.5, -7.0)
	fill.light_color = Color(0.04, 0.48, 0.68)
	fill.light_energy = 7.0
	fill.omni_range = 24.0
	add_child(fill)

	var rim := OmniLight3D.new()
	rim.position = Vector3(5.5, 0.5, 1.5)
	rim.light_color = Color(0.34, 0.05, 0.50)
	rim.light_energy = 5.2
	rim.omni_range = 14.0
	add_child(rim)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(110.0, 110.0)
	floor.mesh = floor_mesh
	floor.position.y = -8.0
	floor.material_override = _material(Color(0.025, 0.060, 0.065), 0.94, 0.0)
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

	# Low, irregular seabed silhouettes: depth cues without clutter.
	for i in 12:
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(0.8, 2.6)
		mesh.height = mesh.radius * rng.randf_range(1.0, 1.6)
		rock.mesh = mesh
		rock.scale = Vector3(rng.randf_range(0.9, 2.1), rng.randf_range(0.28, 0.64), rng.randf_range(0.8, 1.7))
		rock.position = Vector3(rng.randf_range(-18.0, 18.0), -7.15, rng.randf_range(-31.0, 4.0))
		rock.rotation.y = rng.randf_range(-PI, PI)
		rock.material_override = _material(Color(0.025, 0.055, 0.060), 0.97, 0.0)
		add_child(rock)

	# Hero traversal line.
	_add_wrappable_pylon(Vector3(-3.4, -0.8, -9.5), 15.0, 0.62)
	for x in [-6.8, -2.4, 2.4, 6.8]:
		_add_wrappable_pylon(Vector3(x, -0.8, -15.0), 15.0, 0.54)
		_add_wrappable_pylon(Vector3(x, -0.8, -23.0), 15.0, 0.58)

	var pier := StaticBody3D.new()
	pier.name = "PierDeck"
	pier.position = Vector3(0.0, 6.2, -19.0)
	var pier_mesh := MeshInstance3D.new()
	var pier_box := BoxMesh.new()
	pier_box.size = Vector3(17.0, 0.8, 20.0)
	pier_mesh.mesh = pier_box
	pier_mesh.material_override = _material(Color(0.095, 0.080, 0.060), 0.78, 0.03)
	pier.add_child(pier_mesh)
	var pier_collision := CollisionShape3D.new()
	var pier_shape := BoxShape3D.new()
	pier_shape.size = Vector3(17.0, 0.8, 20.0)
	pier_collision.shape = pier_shape
	pier.add_child(pier_collision)
	add_child(pier)

	# Ship-like objective silhouette beyond the pier.
	var hull := MeshInstance3D.new()
	var hull_mesh := SphereMesh.new()
	hull_mesh.radius = 2.0
	hull_mesh.height = 4.0
	hull.mesh = hull_mesh
	hull.position = Vector3(10.5, -1.0, -31.0)
	hull.scale = Vector3(2.7, 0.82, 5.4)
	hull.rotation.z = deg_to_rad(-4.0)
	hull.material_override = _material(Color(0.055, 0.075, 0.085), 0.52, 0.20)
	add_child(hull)

	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(7.0, 1.1, 10.5)
	deck.mesh = deck_mesh
	deck.position = Vector3(10.5, 1.0, -31.0)
	deck.material_override = _material(Color(0.10, 0.12, 0.12), 0.62, 0.12)
	add_child(deck)

	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(4.2, 2.4, 4.2)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(10.5, 2.55, -32.0)
	cabin.material_override = _material(Color(0.12, 0.15, 0.15), 0.54, 0.10)
	add_child(cabin)

	# Tiny suspended lights/particles give scale and depth in the capture.
	for i in 18:
		var mote := MeshInstance3D.new()
		var mote_mesh := SphereMesh.new()
		mote_mesh.radius = rng.randf_range(0.025, 0.065)
		mote_mesh.height = mote_mesh.radius * 2.0
		mote.mesh = mote_mesh
		mote.position = Vector3(rng.randf_range(-11.0, 11.0), rng.randf_range(-4.5, 7.0), rng.randf_range(-29.0, -4.0))
		mote.material_override = _emissive_material(Color(0.02, 0.38, 0.60), rng.randf_range(1.2, 2.4))
		add_child(mote)

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
	kraken.position = Vector3(0.0, 0.2, 2.0)
	add_child(kraken)

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 1.35
	body_mesh.height = 2.3
	body.mesh = body_mesh
	body.position = Vector3(0.0, -0.10, -0.28)
	body.scale = Vector3(1.08, 0.54, 1.02)
	body.material_override = _kraken_skin(Color(0.31, 0.045, 0.42), Color(0.04, 0.45, 0.62), 0.0)
	kraken.add_child(body)

	var mantle := MeshInstance3D.new()
	var mantle_mesh := SphereMesh.new()
	mantle_mesh.radius = 1.30
	mantle_mesh.height = 2.5
	mantle.mesh = mantle_mesh
	mantle.position = Vector3(0.0, 0.42, 0.78)
	mantle.scale = Vector3(0.74, 0.62, 1.12)
	mantle.material_override = _kraken_skin(Color(0.40, 0.065, 0.50), Color(0.03, 0.42, 0.58), 0.8)
	kraken.add_child(mantle)

	var shoulder := MeshInstance3D.new()
	var shoulder_mesh := SphereMesh.new()
	shoulder_mesh.radius = 1.18
	shoulder_mesh.height = 2.0
	shoulder.mesh = shoulder_mesh
	shoulder.position = Vector3(0.0, -0.34, -0.70)
	shoulder.scale = Vector3(1.30, 0.34, 0.95)
	shoulder.material_override = _kraken_skin(Color(0.27, 0.035, 0.36), Color(0.05, 0.34, 0.52), 1.6)
	kraken.add_child(shoulder)

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.18
		eye_mesh.height = 0.36
		eye.mesh = eye_mesh
		eye.position = Vector3(0.72 * side, 0.25, -1.24)
		eye.scale = Vector3(1.05, 0.72, 0.72)
		eye.material_override = _emissive_material(Color(0.20, 0.78, 0.88), 1.6)
		kraken.add_child(eye)

		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.08
		pupil_mesh.height = 0.16
		pupil.mesh = pupil_mesh
		pupil.position = Vector3(0.72 * side, 0.25, -1.39)
		pupil.scale = Vector3(0.48, 1.0, 0.48)
		pupil.material_override = _material(Color(0.02, 0.015, 0.025), 0.1, 0.0)
		kraken.add_child(pupil)

	for t in TENTACLE_COUNT:
		var chain: Array = []
		var fan_t: float = float(t) / float(maxi(TENTACLE_COUNT - 1, 1))
		var fan_angle: float = lerpf(-1.12, 1.12, fan_t)
		var parent := Node3D.new()
		parent.position = Vector3(sin(fan_angle) * 0.82, -0.56, -0.74 + absf(fan_angle) * 0.12)
		parent.rotation.y = fan_angle
		parent.rotation.x = 0.05 + absf(fan_angle) * 0.03
		kraken.add_child(parent)
		tentacle_bases.append(parent)

		var current_parent := parent
		for s in SEGMENTS_PER_TENTACLE:
			var joint := Node3D.new()
			joint.position = Vector3(0.0, -0.045, -0.56)
			current_parent.add_child(joint)
			chain.append(joint)
			current_parent = joint

		tentacle_segments.append(chain)

		var tube := MeshInstance3D.new()
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var phase: float = float(t) * 0.77
		tube.material_override = _kraken_skin(
			Color(0.30 + 0.025 * float(t % 2), 0.035, 0.42 + 0.025 * float(t % 3)),
			Color(0.02, 0.42, 0.58),
			phase
		)
		kraken.add_child(tube)
		tentacle_visuals.append(tube)

		# Readable sucker rhythm along the underside. These are presentation
		# geometry only; actual adhesion remains in the contact planner.
		for s in range(1, chain.size(), 2):
			var sucker := MeshInstance3D.new()
			var sucker_mesh := SphereMesh.new()
			sucker_mesh.radius = maxf(0.055, 0.115 * (1.0 - float(s) / float(chain.size()) * 0.68))
			sucker_mesh.height = sucker_mesh.radius * 0.48
			sucker.mesh = sucker_mesh
			sucker.position = Vector3(0.0, -0.13, -0.24)
			sucker.scale = Vector3(1.0, 0.42, 1.0)
			sucker.material_override = _emissive_material(Color(0.44, 0.72, 0.76), 0.42)
			var sucker_joint: Node3D = chain[s]
			sucker_joint.add_child(sucker)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 74.0
	camera.near = 0.08
	add_child(camera)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "KRAKEN"
	title.position = Vector2(26, 22)
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Color(0.72, 0.91, 0.95, 0.78)
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

	controls_label = Label.new()
	controls_label.text = "WASD swim   SHIFT burst   Q grapple   C ghost   E hunt"
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	controls_label.position = Vector2(-250, -38)
	controls_label.size = Vector2(500, 28)
	controls_label.modulate = Color(0.78, 0.91, 0.93, 0.45)
	layer.add_child(controls_label)

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

	if capture_demo and move.length_squared() < 0.01:
		move = Vector3(0.0, -0.03, -1.0).normalized()
		speed = MOVE_SPEED * 1.15

	var target_velocity := move * speed
	velocity = velocity.lerp(target_velocity, 1.0 - exp(-4.8 * delta))

	var grapple_active: bool = Input.is_action_pressed("grapple")
	if grapple_active and contact_planner.has_primary_contact():
		var pull_vector: Vector3 = contact_planner.get_primary_point() - kraken.global_position
		var contact_distance: float = pull_vector.length()
		if contact_distance > 0.2:
			var pull_direction: Vector3 = pull_vector / contact_distance
			var radial_error: float = contact_distance - GRAPPLE_ORBIT_RADIUS
			var radial_accel: float = clampf(radial_error * 9.0, -GRAPPLE_ACCEL, GRAPPLE_ACCEL)
			velocity += pull_direction * radial_accel * delta

			# Near the anchor, kill only radial velocity. Tangential velocity remains,
			# which turns a grapple into a swing and makes release a slingshot.
			if absf(radial_error) < 0.75:
				var radial_speed: float = velocity.dot(pull_direction)
				velocity -= pull_direction * radial_speed * 0.42

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
	var wants_grapple: bool = Input.is_action_pressed("grapple")
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
	_update_tentacle_meshes()

func _update_tentacle_meshes() -> void:
	for t in mini(tentacle_segments.size(), tentacle_visuals.size()):
		var points := PackedVector3Array()
		var base: Node3D = tentacle_bases[t]
		points.append(kraken.to_local(base.global_position))
		var chain: Array = tentacle_segments[t]
		for joint_node in chain:
			var joint: Node3D = joint_node
			points.append(kraken.to_local(joint.global_position))
		var tube: MeshInstance3D = tentacle_visuals[t]
		tube.mesh = TentacleTubeClass.build(points, 0.31, 0.065, 11)

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
	var speed_ratio: float = clampf(velocity.length() / GRAPPLE_MAX_SPEED, 0.0, 1.0)
	var yaw_basis := Basis(Vector3.UP, yaw)
	var dynamic_distance: float = lerpf(CAMERA_DISTANCE + 0.8, CAMERA_DISTANCE + 1.8, speed_ratio)
	var horizontal_back := yaw_basis * Vector3(0.0, 0.0, dynamic_distance)
	var side_offset := yaw_basis * Vector3(0.85, 0.0, 0.0)
	var desired := kraken.global_position + horizontal_back + side_offset + Vector3(0.0, CAMERA_HEIGHT + 0.75 + pitch * 2.4, 0.0)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-8.5 * delta))
	camera.fov = lerpf(72.0, 80.0, speed_ratio)

	var forward := -kraken.global_transform.basis.z.normalized()
	var look_target := kraken.global_position + forward * lerpf(2.6, 4.5, speed_ratio) + Vector3(0.0, -0.35, 0.0)
	camera.look_at(look_target, Vector3.UP)

func _update_hud() -> void:
	hud_depth.text = "DEPTH  %+.1f m" % (-kraken.position.y)
	hud_speed.text = "SPEED  %.1f m/s" % velocity.length()
	hud_mode.text = "MOTOR  " + motor.intent_name()
	hud_contact.text = "CONTACT  LOCK" if contact_planner.has_primary_contact() else "CONTACT  SCANNING"

func _kraken_skin(base_color: Color, accent_color: Color, phase: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color;
uniform vec4 accent_color : source_color;
uniform float phase = 0.0;

void fragment() {
	float bands = 0.5 + 0.5 * sin((VERTEX.x * 4.2 + VERTEX.z * 3.1 + VERTEX.y * 2.3) + phase);
	float mottled = smoothstep(0.30, 0.78, bands);
	vec3 skin = mix(base_color.rgb * 0.72, base_color.rgb * 1.16, mottled);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.4);
	ALBEDO = skin;
	ROUGHNESS = 0.34;
	METALLIC = 0.03;
	EMISSION = accent_color.rgb * rim * (0.10 + 0.16 * mottled);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", base_color)
	mat.set_shader_parameter("accent_color", accent_color)
	mat.set_shader_parameter("phase", phase)
	return mat

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.28
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

