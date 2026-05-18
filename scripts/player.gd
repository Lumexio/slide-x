extends KinematicBody

onready var camera_mount: Spatial = $camera_mount
onready var camera: Camera = $camera_mount/Camera
onready var camera_ray: RayCast = $camera_mount/CameraRay
onready var animation_player: AnimationPlayer = null
onready var visuals: Spatial = $visuals

export(PackedScene) var character_scene = preload("res://scenes/characters/menu/kinetic-chad.tscn")
export(Vector3) var character_rotation_degrees := Vector3(0, 180, 0)

# Movement settings
export(float) var walking_speed := 3.0
export(float) var running_speed := 7.0
export(float) var JUMP_VELOCITY := 8.0
var gravity := 13.5

# Look control settings
export(bool) var mouse_look_enabled := true
export(float) var mouse_sensitivity := 0.1
export(float) var stick_look_speed := 2.5
export(float) var stick_deadzone := 0.2
export(int) var left_stick_x_axis := 0
export(int) var left_stick_y_axis := 1
export(int) var right_stick_x_axis := 2
export(int) var right_stick_y_axis := 3
export(float) var min_pitch_degrees := -65.0
export(float) var max_pitch_degrees := 65.0
export(bool) var invert_look_y := false
export(float) var camera_collision_margin := 0.2
export(float) var camera_lag_speed := 12.0
export(float) var look_smooth_speed := 12.0
export(float) var locomotion_blend_time := 0.12
export(float) var attack_blend_time := 0.06
export(float) var combo_shake_strength := 0.05
export(float) var combo_shake_decay := 8.0
export(float) var combo_roll_degrees := 2.5
export(float) var combo_rumble_strong := 0.9
export(float) var combo_rumble_weak := 0.4
export(float) var combo_rumble_time := 0.12

# --- Independent Dash Settings ---
export(float) var HARD_PUNCH_DASH_SPEED := 30.0  # Very fast speed
export(float) var HARD_PUNCH_DASH_TIME := 0.15   # Very short time (determines distance)
export(float) var TORNADO_KICK_DASH_SPEED := 15.0
export(float) var TORNADO_KICK_DASH_TIME := 0.1

var velocity := Vector3.ZERO
var is_attacking := false
var current_attack_dash_speed := 0.0
var _pitch := 0.0
var _target_yaw := 0.0
var _target_pitch := 0.0
var _camera_default_offset := Vector3.ZERO
var _camera_base_rotation := Vector3.ZERO
var _shake_amount := 0.0

# --- Double Jump Variables ---
var jump_count := 0
export(int) var extra_jumps := 1

# Combo Counters
var punch_count := 0
var kick_count := 0

func _ready() -> void:
	if OS.get_name() == "Vita":
		mouse_look_enabled = false
		stick_look_speed = 2.0
		stick_deadzone = 0.25
	if mouse_look_enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_setup_character_visuals()
	_pitch = clamp(camera_mount.rotation.x, deg2rad(min_pitch_degrees), deg2rad(max_pitch_degrees))
	_target_yaw = rotation.y
	_target_pitch = _pitch
	if camera:
		_camera_default_offset = camera.transform.origin
		_camera_base_rotation = camera.rotation
	if camera_ray:
		camera_ray.enabled = true
		camera_ray.cast_to = _camera_default_offset
		camera_ray.exclude_parent = true
		camera_ray.add_exception(self)


func _setup_character_visuals() -> void:
	if visuals == null:
		return
	var scene: PackedScene = character_scene
	if scene == null:
		scene = load("res://scenes/characters/menu/kinetic-chad.tscn") as PackedScene
	if scene == null:
		push_error("Failed to load player character scene.")
		return
	var instance = scene.instance()
	if instance == null:
		push_error("Failed to instance player character scene.")
		return
	instance.name = "character_model"
	visuals.add_child(instance)
	instance.rotation_degrees = character_rotation_degrees
	animation_player = instance.get_node_or_null("AnimationPlayer")
	if animation_player == null:
		animation_player = instance.find_node("AnimationPlayer", true, false)
	if animation_player == null:
		push_error("Player character is missing AnimationPlayer.")
	var old_model = visuals.get_node_or_null("meele-guy")
	if old_model != null:
		old_model.queue_free()

func _input(event: InputEvent) -> void:
	if not mouse_look_enabled:
		return
	if event is InputEventMouseMotion:
		var yaw = deg2rad(-event.relative.x * mouse_sensitivity)
		var pitch = deg2rad(-event.relative.y * mouse_sensitivity)
		if invert_look_y:
			pitch = -pitch
		_apply_look(yaw, pitch)

func _physics_process(delta: float) -> void:
	_apply_stick_look(delta)
	_update_look_smoothing(delta)

	# 1. Apply Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1 
		jump_count = 0

	# 2. Handle Attacks
	if is_on_floor() and not is_attacking:
		if Input.is_action_just_pressed("elbow"):
			handle_elbow_logic()
		elif Input.is_action_just_pressed("punch"):
			if Input.is_action_pressed("elbow_mod"):
				handle_elbow_logic()
			else:
				handle_punch_logic()
		elif Input.is_action_just_pressed("kick"):
			handle_kick_logic()

	# 3. Handle Jump & Double Jump
	if Input.is_action_just_pressed("jump") and not is_attacking:
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			play_anim_if_not("jumping")
			jump_count += 1
		elif jump_count <= extra_jumps:
			velocity.y = JUMP_VELOCITY * 1.5 
			play_anim_if_not("jumping")
			jump_count += 1

	# 4. Movement Logic
	var move_vec = get_input_direction()
	
	if not is_attacking:
		var target_speed = running_speed if Input.is_action_pressed("run") else walking_speed
		
		if is_on_floor():
			velocity.x = move_vec.x * target_speed
			velocity.z = move_vec.z * target_speed
			
			if move_vec.length() > 0:
				var look_target = global_transform.origin + move_vec
				visuals.look_at(look_target, Vector3.UP)
				
				if target_speed == running_speed:
					play_anim_if_not("run")
				else:
					play_anim_if_not("walk")
			else:
				play_anim_if_not("idle")
		else:
			var air_control_factor = 0.1 
			velocity.x = lerp(velocity.x, move_vec.x * target_speed, air_control_factor)
			velocity.z = lerp(velocity.z, move_vec.z * target_speed, air_control_factor)
			play_anim_if_not("jumping")
			
			if move_vec.length() > 0:
				var look_target = global_transform.origin + move_vec
				visuals.look_at(look_target, Vector3.UP)
	else:
		# Dash Logic: Moves at current_attack_dash_speed
		# This becomes 0.0 automatically when the timer finishes
		var dash_dir = -visuals.global_transform.basis.z.normalized()
		velocity.x = dash_dir.x * current_attack_dash_speed
		velocity.z = dash_dir.z * current_attack_dash_speed

	velocity = move_and_slide(velocity, Vector3.UP)
	_update_camera_collision(delta)

# --- Sequential Attack Handlers ---

func handle_punch_logic() -> void:
	punch_count += 1
	if punch_count <= 2:
		_trigger_combo_feedback(0.5)
		play_action("punch", 0, 0, 1.2) # Fast regular punches
	elif punch_count <= 4:
		_trigger_combo_feedback(0.6)
		play_action("punch-elbow", 0, 0, 1.0)
	else:
		# Hard punch: Very fast dash, but a slower, heavier animation (0.8 speed)
		_trigger_combo_feedback(1.2)
		play_action("punch-hard", HARD_PUNCH_DASH_SPEED, HARD_PUNCH_DASH_TIME, 2)
		punch_count = 0

func handle_kick_logic() -> void:
	kick_count += 1
	if kick_count <= 3:
		_trigger_combo_feedback(0.6)
		play_action("kick")
	else:
		_trigger_combo_feedback(1.0)
		play_action("kick-tornado", TORNADO_KICK_DASH_SPEED, TORNADO_KICK_DASH_TIME)
		kick_count = 0

func handle_elbow_logic() -> void:
	_trigger_combo_feedback(0.8)
	play_action("punch-elbow", 0, 0, 1.0)
	punch_count = 0
	kick_count = 0

# --- Helper Functions ---

func get_input_direction() -> Vector3:
	var input = Vector3.ZERO
	input.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input.z = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if input.length() > 1.0:
		input = input.normalized()
	return (transform.basis.x * input.x + transform.basis.z * input.z)

func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	_target_yaw += yaw_delta
	_target_pitch = clamp(_target_pitch + pitch_delta, deg2rad(min_pitch_degrees), deg2rad(max_pitch_degrees))

func _update_look_smoothing(delta: float) -> void:
	var t = clamp(look_smooth_speed * delta, 0.0, 1.0)
	rotation.y = lerp_angle(rotation.y, _target_yaw, t)
	_pitch = lerp(_pitch, _target_pitch, t)
	camera_mount.rotation.x = _pitch

func _apply_stick_look(delta: float) -> void:
	var joy_id = _get_primary_joypad()
	if joy_id < 0:
		return
	var axis_x = _apply_deadzone(Input.get_joy_axis(joy_id, right_stick_x_axis), stick_deadzone)
	var axis_y = _apply_deadzone(Input.get_joy_axis(joy_id, right_stick_y_axis), stick_deadzone)
	if axis_x == 0.0 and axis_y == 0.0:
		return
	var yaw = -axis_x * stick_look_speed * delta
	var pitch = -axis_y * stick_look_speed * delta
	if invert_look_y:
		pitch = -pitch
	_apply_look(yaw, pitch)

func _update_camera_collision(delta: float) -> void:
	if not camera or not camera_ray:
		return
	var target_local = _camera_default_offset
	camera_ray.cast_to = _camera_default_offset
	camera_ray.force_raycast_update()
	if camera_ray.is_colliding():
		var hit_point = camera_ray.get_collision_point()
		var hit_normal = camera_ray.get_collision_normal()
		var target_global = hit_point + hit_normal * camera_collision_margin
		target_local = camera_mount.to_local(target_global)
	var t = clamp(camera_lag_speed * delta, 0.0, 1.0)
	var base_local = camera.translation.linear_interpolate(target_local, t)
	var shake_offset = Vector3.ZERO
	var roll = 0.0
	if _shake_amount > 0.0:
		_shake_amount = max(_shake_amount - combo_shake_decay * delta, 0.0)
		shake_offset = Vector3(_randf_range(-1.0, 1.0), _randf_range(-1.0, 1.0), 0.0) * _shake_amount
		var roll_scale = 0.0
		if combo_shake_strength > 0.0:
			roll_scale = _shake_amount / combo_shake_strength
		roll = deg2rad(combo_roll_degrees) * roll_scale * _randf_range(-1.0, 1.0)
	camera.translation = base_local + shake_offset
	camera.rotation = Vector3(_camera_base_rotation.x, _camera_base_rotation.y, roll)

func _trigger_combo_feedback(strength_scale := 1.0) -> void:
	_shake_amount = max(_shake_amount, combo_shake_strength * strength_scale)
	_start_combo_rumble(strength_scale)

func _start_combo_rumble(strength_scale: float) -> void:
	var joy_id = _get_primary_joypad()
	if joy_id < 0:
		return
	var strong = clamp(combo_rumble_strong * strength_scale, 0.0, 1.0)
	var weak = clamp(combo_rumble_weak * strength_scale, 0.0, 1.0)
	Input.start_joy_vibration(joy_id, weak, strong, combo_rumble_time)

func _randf_range(min_val: float, max_val: float) -> float:
	return rand_range(min_val, max_val)

func _apply_deadzone(value: float, deadzone: float) -> float:
	if abs(value) < deadzone:
		return 0.0
	return value

func _get_primary_joypad() -> int:
	var pads = Input.get_connected_joypads()
	if pads.size() == 0:
		return -1
	return pads[0]

# Updated to handle independent Dash Time
func play_action(anim_name: String, dash_speed := 0.0, dash_time := 0.0, anim_speed := 1.0):
	if animation_player == null:
		return
	var anim = animation_player.get_animation(anim_name)
	if anim == null:
		push_error("Missing attack animation: " + anim_name)
		return
	is_attacking = true
	
	# Set the speed before playing
	animation_player.playback_speed = anim_speed
	animation_player.play(anim_name, attack_blend_time)
	
	# Handle the dash
	current_attack_dash_speed = dash_speed
	if dash_time > 0:
		yield(get_tree().create_timer(dash_time), "timeout")
		current_attack_dash_speed = 0.0
	
	# Wait for animation
	var wait_time = anim.length
	if anim.loop or wait_time <= 0.0:
		wait_time = 0.35
	else:
		wait_time = wait_time / max(anim_speed, 0.01)
	yield(get_tree().create_timer(wait_time), "timeout")
	
	# RESET speed to normal so walk/run aren't affected
	animation_player.playback_speed = 1.0
	current_attack_dash_speed = 0.0
	is_attacking = false

func play_anim_if_not(anim_name: String) -> void:
	if animation_player == null:
		return
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, locomotion_blend_time)
