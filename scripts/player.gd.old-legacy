extends KinematicBody

onready var camera_mount = $camera_mount
onready var animation_player = $"visuals/meele-guy/AnimationPlayer"
onready var visuals = $visuals

# Movement settings
export var walking_speed = 3.0
export var running_speed = 7.0
export var JUMP_VELOCITY = 8.0
var gravity = 13.5

# --- Independent Dash Settings ---
export var HARD_PUNCH_DASH_SPEED = 30.0  # Very fast speed
export var HARD_PUNCH_DASH_TIME = 0.15   # Very short time (determines distance)
export var TORNADO_KICK_DASH_SPEED = 15.0
export var TORNADO_KICK_DASH_TIME = 0.1

var velocity = Vector3.ZERO
var is_attacking = false
var current_attack_dash_speed = 0.0 

# --- Double Jump Variables ---
var jump_count = 0
export var extra_jumps = 1 

# Combo Counters
var punch_count = 0
var kick_count = 0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg2rad(-event.relative.x * 0.1))
		camera_mount.rotate_x(deg2rad(-event.relative.y * 0.1))

func _physics_process(delta):
	# 1. Apply Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1 
		jump_count = 0

	# 2. Handle Attacks
	if is_on_floor() and not is_attacking:
		if Input.is_action_just_pressed("punch"):
			handle_punch_logic()
		elif Input.is_action_just_pressed("kick"):
			handle_kick_logic()

	# 3. Handle Jump & Double Jump
	if Input.is_action_just_pressed("jump") and not is_attacking:
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			animation_player.stop() 
			animation_player.play("jumping")
			jump_count += 1
		elif jump_count <= extra_jumps:
			velocity.y = JUMP_VELOCITY * 1.5 
			animation_player.stop() 
			animation_player.play("jumping")
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

# --- Sequential Attack Handlers ---

func handle_punch_logic():
	punch_count += 1
	if punch_count <= 2:
		play_action("punch", 0, 0, 1.2) # Fast regular punches
	elif punch_count <= 4:
		play_action("punch-elbow", 0, 0, 1.0)
	else:
		# Hard punch: Very fast dash, but a slower, heavier animation (0.8 speed)
		play_action("punch-hard", HARD_PUNCH_DASH_SPEED, HARD_PUNCH_DASH_TIME, 2)
		punch_count = 0

func handle_kick_logic():
	kick_count += 1
	if kick_count <= 3:
		play_action("kick")
	else:
		play_action("kick-tornado", TORNADO_KICK_DASH_SPEED, TORNADO_KICK_DASH_TIME)
		kick_count = 0

# --- Helper Functions ---

func get_input_direction():
	var input = Vector3.ZERO
	if Input.is_action_pressed("ui_up"): input.z -= 1
	if Input.is_action_pressed("ui_down"): input.z += 1
	if Input.is_action_pressed("ui_left"): input.x -= 1
	if Input.is_action_pressed("ui_right"): input.x += 1
	input = input.normalized()
	return (transform.basis.x * input.x + transform.basis.z * input.z).normalized()

# Updated to handle independent Dash Time
func play_action(anim_name, dash_speed = 0.0, dash_time = 0.0, anim_speed = 1.0):
	is_attacking = true
	
	# Set the speed before playing
	animation_player.playback_speed = anim_speed
	animation_player.play(anim_name)

	
	# Handle the dash
	current_attack_dash_speed = dash_speed
	if dash_time > 0:
		yield(get_tree().create_timer(dash_time), "timeout")
		current_attack_dash_speed = 0.0
	
	# Wait for animation
	if animation_player.is_playing():
		yield(animation_player, "animation_finished")
	
	# RESET speed to normal so walk/run aren't affected
	animation_player.playback_speed = 1.0
	current_attack_dash_speed = 0.0
	is_attacking = false

func play_anim_if_not(anim_name):
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)
