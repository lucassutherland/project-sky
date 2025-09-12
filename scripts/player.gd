extends CharacterBody3D

@onready var camera_pivot: Node3D = $CameraPivot
@onready var tilt_pivot: Node3D = $VisualPivot   # holds the mesh/visuals only

@export var sensitivity := 0.5
const BASE_SPEED := 15.0
const JUMP_VELOCITY := 10.0
var paused := false

# ------- Tilt tuning -------
@export var max_pitch_deg := 10.0          # max nod forward/back
@export var max_bank_deg := 8.0            # max lean left/right
@export var pitch_from_speed := 0.55       # deg per m/s
@export var pitch_from_accel := 0.25       # deg per m/s^2
@export var bank_from_accel := 0.35        # deg per m/s^2
@export var tilt_lerp_speed := 10.0        # smoothing for tilt
@export var accel_smooth := 0.15           # smoothing for acceleration

# quick sign flips if directions feel wrong
@export var pitch_sign := -1.0              # set -1 if pitch is inverted
@export var bank_sign := -1.0               # set -1 if bank is inverted

var _prev_velocity := Vector3.ZERO
var _smooth_accel := Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and !paused:
		# yaw the body
		rotate_y(deg_to_rad(event.relative.x * -sensitivity))
		# pitch the camera only
		camera_pivot.rotate_x(deg_to_rad(event.relative.y * -sensitivity))
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI / 2, PI / 8)


func _physics_process(delta: float) -> void:
	# gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# pause toggle
	if Input.is_action_just_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
		paused = !paused

	# jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# movement input -> world-space direction following body yaw
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	
	var speed = BASE_SPEED;
	if (Input.is_key_pressed(KEY_SHIFT) and is_on_floor()):
		speed *= 2;
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	# --- Tilt math ---
	var raw_accel = (velocity - _prev_velocity) / max(delta, 1e-6)
	_smooth_accel = lerp(_smooth_accel, raw_accel, clamp(accel_smooth, 0.0, 1.0))

	# localize to player's yaw
	var to_local = transform.basis.inverse()
	var v_local = to_local * velocity
	var a_local = to_local * _smooth_accel

	# forward is -Z in Godot
	var forward_speed = -v_local.z
	var forward_accel = -a_local.z
	var lateral_accel = a_local.x

	var pitch_raw = forward_speed * pitch_from_speed + forward_accel * pitch_from_accel
	var bank_raw  = lateral_accel * bank_from_accel

	var pitch_deg = clamp(pitch_raw * pitch_sign, -max_pitch_deg, max_pitch_deg)
	var bank_deg  = clamp(bank_raw  * bank_sign,  -max_bank_deg,  max_bank_deg)

	# smoothly apply to the visuals
	var target_pitch = deg_to_rad(pitch_deg)
	var target_bank  = deg_to_rad(bank_deg)

	tilt_pivot.rotation.x = lerp_angle(tilt_pivot.rotation.x, target_pitch, tilt_lerp_speed * delta)
	tilt_pivot.rotation.z = lerp_angle(tilt_pivot.rotation.z, target_bank,  tilt_lerp_speed * delta)

	_prev_velocity = velocity

	move_and_slide()
