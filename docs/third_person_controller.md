# Third-Person Character Controller

This document explains the state-machine-based third-person character controller and camera system ported from the Lumexio/3d-character-testing repository.

## Architecture Overview

The controller uses a modular state machine pattern that separates concerns into distinct, reusable components:

### Core Components

#### 1. State Machine Core (`src/Main/StateMachine/`)

- **State.gd**: Base class for all states in the system. Provides lifecycle callbacks (`enter`, `exit`, `physics_process`, etc.) and automatic parent state delegation for hierarchical state machines.

- **StateMachine.gd**: Manages state transitions and delegates engine callbacks to the active state. Can be nested for hierarchical state machines.

#### 2. Player (`src/Player/`)

- **Player.gd**: Main player controller (KinematicBody root) that provides references to the camera rig, visual representation (skin), and state machine. This is the entry point for the player character.

```gdscript
class_name Player
extends KinematicBody

onready var camera: CameraRig = $CameraRig
onready var skin: Mannequiny = $visuals
onready var state_machine: StateMachine = $StateMachine
```

- **PlayerState.gd**: Base class for all player-specific states. Extends State and adds references to the player and skin for easy access in child states.

- **Mannequiny.gd**: Animation controller that manages AnimationTree transitions. Maps logical states to actual animations from the melee-guy model.

#### 3. Player States (`src/Player/States/`)

The player uses a hierarchical state machine with the following structure:

- **Move.gd**: Parent state for all ground-based movement. Handles:
  - Camera-relative input (WASD keys)
  - Player rotation toward movement direction
  - Physics-based movement with move_and_slide
  - Gravity application
  - Jump input detection
  - Transition to Air state when jumping

- **Idle.gd**: Active when player has no movement input on the ground. Transitions to Run when velocity increases, or Air when falling.

- **Run.gd**: Active when player is moving on the ground. Transitions to Idle when stopped, or Air when leaving the ground.

- **Air.gd**: Handles jump and fall physics. Transitions back to Idle when landing.

#### 4. Camera System (`src/Player/Camera/`)

- **CameraRig.tscn/CameraRig.gd**: Root camera controller containing:
  - SpringArm for collision-aware distance management
  - InterpolatedCamera for smooth following
  - AimRay (RayCast) for targeting
  - AimTarget (Sprite3D) for visual feedback
  - StateMachine with Default and Aim states

- **CameraState.gd**: Base class for camera states with references to the camera rig.

- **Camera/States/Camera.gd**: Parent camera state handling:
  - Mouse look with configurable sensitivity and inversion
  - Gamepad look support
  - Zoom in/out with mouse wheel
  - Auto-rotation to follow player movement direction
  - Smooth camera positioning

- **Camera/States/Default.gd**: Normal third-person camera mode. Delegates to parent Camera state and allows toggling to Aim mode.

- **Camera/States/Aim.gd**: Over-the-shoulder aiming mode with:
  - Narrowed field of view
  - Camera offset to character's shoulder
  - Aim target projection on environment
  - Fire action support

- **SpringArm.gd**: Custom SpringArm extension with zoom control using a normalized 0-1 value.

- **AimTarget.gd**: Visual sprite that projects onto surfaces for aiming feedback.

## Animation Mapping

The Mannequiny animation controller maps logical states to the melee-guy model's animations:

| Logical State | Animation Name | Usage |
|--------------|----------------|-------|
| IDLE | idle | Standing still |
| RUN | run | Walking/running (no speed blend yet) |
| AIR | jumping | Jump and fall |
| LAND | idle | Landing (no dedicated anim) |

### Available Animations (Future Use)

The melee-guy model includes additional animations that can be integrated for combat:

- `walk` - Walking animation (not currently used)
- `kick` - Basic kick attack
- `punch` - Basic punch attack  
- `punch-elbow` - Elbow strike combo
- `punch-hard` - Heavy punch with dash
- `kick-tornado` - Tornado kick with dash
- `jump-back` - Backward jump (not currently used)

To add combat or more animations, modify `Mannequiny.gd` to include additional enum values and transition logic.

## Tweaking Movement Behavior

### Movement Parameters

Edit `src/Player/States/Move.gd` to adjust core movement:

```gdscript
export var max_speed: = 12.0      # Maximum movement speed cap
export var move_speed: = 10.0     # Base movement speed
export var gravity = -80.0        # Gravity force (negative for down)
export var jump_impulse = 25      # Initial jump velocity
```

**Tips:**
- Increase `move_speed` for faster movement
- Increase `jump_impulse` for higher jumps
- Adjust `gravity` for different jump feel (lower = floatier)
- `max_speed` prevents excessive speed from combining forces

### State Transitions

To modify when states change, edit the `physics_process` or condition checks in each state:

**Example: Make player transition to Idle faster**
```gdscript
# In src/Player/States/Run.gd
func physics_process(delta: float) -> void:
    _parent.physics_process(delta)
    if _parent.velocity.length() < 0.1:  # Changed from 0.001 to 0.1
        _state_machine.transition_to("Move/Idle")
```

## Tweaking Camera Behavior

### Camera Parameters

Edit `src/Player/Camera/States/Camera.gd` for camera feel:

```gdscript
export var is_y_inverted: = false           # Invert vertical look
export var fov_default: = 70.0              # Field of view (degrees)
export var deadzone := PI/10                # Auto-rotate deadzone
export var sensitivity_gamepad: = Vector2(2.5, 2.5)  # Gamepad look speed
export var sensitivity_mouse: = Vector2(0.1, 0.1)    # Mouse look speed
```

**Tips:**
- Increase `sensitivity_mouse` for faster camera rotation
- Set `is_y_inverted = true` for inverted Y-axis
- Increase `fov_default` for wider view (70-90 typical)
- Decrease `deadzone` for more aggressive auto-rotation

### Camera Distance

Edit `src/Player/Camera/SpringArm.gd`:

```gdscript
export var length_range: = Vector2(3.0, 6.0)  # Min and max camera distance
```

The camera distance interpolates between `length_range.x` (zoomed in) and `length_range.y` (zoomed out) based on the zoom value (0-1).

### Aim Mode

Edit `src/Player/Camera/States/Aim.gd`:

```gdscript
export var fov: = 40.0                         # FOV when aiming (narrower)
export var offset_camera: = Vector3(0.75, -0.7, 0)  # Camera offset (right, up, forward)
```

## Input Configuration

The following input actions are configured in `project.godot`:

### Movement
- `move_front` (W) - Move forward
- `move_back` (S) - Move backward
- `move_left` (A) - Strafe left
- `move_right` (D) - Strafe right
- `jump` (Space) - Jump

### Camera
- `toggle_aim` (Right Mouse Button) - Toggle aiming mode
- `fire` (Left Mouse Button) - Fire/confirm in aim mode
- `zoom_in` (Mouse Wheel Up) - Zoom camera in
- `zoom_out` (Mouse Wheel Down) - Zoom camera out
- `look_left`, `look_right`, `look_up`, `look_down` - Gamepad camera (not bound by default)

### Legacy Combat (from original system)
- `run` (Shift) - Run toggle
- `punch` (I) - Punch combos
- `kick` (O) - Kick combos
- `elbow` (P) - Elbow attack

## Extending the System

### Adding New Player States

1. Create a new script extending `PlayerState`:

```gdscript
extends PlayerState

func enter(msg: Dictionary = {}) -> void:
    # Initialize state
    pass

func physics_process(delta: float) -> void:
    # Update state
    pass

func exit() -> void:
    # Clean up state
    pass
```

2. Add the state as a child of the appropriate parent state in the scene tree (usually under `Move` for ground states).

3. Transition to your state from other states:

```gdscript
_state_machine.transition_to("Move/YourNewState")
```

### Adding New Animations

1. Add the animation to the AnimationTree state machine in the Godot editor.

2. Update `Mannequiny.gd` to add your logical state:

```gdscript
enum States {IDLE, RUN, AIR, LAND, YOUR_NEW_STATE}

func transition_to(state_id: int) -> void:
    match state_id:
        States.YOUR_NEW_STATE:
            _playback.travel("your_animation_name")
```

3. Call `skin.transition_to(skin.States.YOUR_NEW_STATE)` from your player state.

### Adding Combat System

The original combat system can be integrated by:

1. Creating new states under `Move` for each attack type:
   - `Attack.gd` - Base attack state
   - `Punch.gd`, `Kick.gd`, etc. - Specific attack states

2. Handling attack input in appropriate states (Idle/Run):

```gdscript
func unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("punch"):
        _state_machine.transition_to("Move/Punch")
```

3. Implementing attack logic with dash mechanics (see `scripts/player.gd.backup` for reference).

## Troubleshooting

### Camera not following player
- Ensure `CameraRig` is a child of the `Player` root node
- Verify `Player.gd` has `onready var camera: CameraRig = $CameraRig`
- Check that `InterpolatedCamera` has `current = true` and correct target path

### Player not moving
- Verify input actions exist in `project.godot`
- Check that `StateMachine` has `initial_state` set to `Move/Idle`
- Ensure `Player.gd` has correct onready references

### Animations not playing
- Verify AnimationTree is active
- Check AnimationTree's AnimationPlayer path is correct
- Ensure state names in AnimationTree match those in `Mannequiny.gd`
- Verify animations exist in the AnimationPlayer

### Wrong movement direction
- Movement is camera-relative - ensure `CameraRig` is working
- Verify mouse input is captured: `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)`

## Technical Notes

### Godot 3.5 Compatibility
All scripts use Godot 3.5 APIs and avoid Godot 4.x features:
- Uses `class_name` instead of `@class_name`
- Uses `onready` instead of `@onready`
- Uses `export` instead of `@export`
- Compatible resource formats

### Camera-Relative Movement
Movement input (WASD) is transformed relative to camera orientation:
```gdscript
var forwards: Vector3 = player.camera.global_transform.basis.z * input_direction.z
var right: Vector3 = player.camera.global_transform.basis.x * input_direction.x
var move_direction: = forwards + right
```

This ensures pressing W always moves forward relative to where the camera is looking.

### State Machine Benefits
- **Modularity**: States are self-contained and reusable
- **Maintainability**: Easy to modify individual behaviors
- **Debuggability**: Clear state transitions
- **Extensibility**: Add new states without modifying existing ones

## Future Enhancements

Potential improvements to consider:

1. **Animation Blending**: Add walk/run speed blending using AnimationTree blend spaces
2. **Strafing**: Add strafe-walk and strafe-run animations
3. **Combat Integration**: Port full combat system from `scripts/player.gd.backup`
4. **Dodge/Roll**: Add evasive maneuvers with invincibility frames
5. **Climb/Vault**: Add traversal mechanics for obstacles
6. **Ledge Grab**: Detect and grab ledges when falling near them

## References

- Original implementation: [Lumexio/3d-character-testing](https://github.com/Lumexio/3d-character-testing)
- State machine tutorial: [GDQuest State Machine](https://www.gdquest.com/tutorial/godot/design-patterns/finite-state-machine/)
- Godot 3.5 docs: [docs.godotengine.org/en/3.5](https://docs.godotengine.org/en/3.5/)
