# State Machine Integration Guide for slide-x

> **Note**: This document has been superseded by the comprehensive [Third-Person Controller Guide](third_person_controller.md).  
> Please refer to that document for complete documentation on architecture, usage, and customization.

This document provides step-by-step instructions for manually integrating the state machine into the existing player scene.

## Quick Reference

For detailed information on:
- **Architecture overview** → See [third_person_controller.md](third_person_controller.md#architecture-overview)
- **Tweaking movement/camera** → See [third_person_controller.md](third_person_controller.md#tweaking-movement-behavior)
- **Animation mapping** → See [third_person_controller.md](third_person_controller.md#animation-mapping)
- **Extending the system** → See [third_person_controller.md](third_person_controller.md#extending-the-system)

## Manual Integration Overview

The third-person character controller has been ported with all scripts and assets in place. However, **manual scene setup in the Godot editor is required** because:

1. slide-x uses `AnimationPlayer` while the state machine expects `AnimationTree`
2. Scene node hierarchies cannot be automatically modified via scripts
3. The existing `scenes/player.tscn` has been preserved to maintain compatibility

**Files that have been added:**
- ✅ State machine core (`src/Main/StateMachine/`)
- ✅ Player controller scripts (`src/Player/`)
- ✅ Movement states (`src/Player/States/`)
- ✅ Camera rig and states (`src/Player/Camera/`)
- ✅ Input mappings (`project.godot`)
- ✅ Aim reticle asset (`assets/2d/reticle.png`)

**What needs manual setup:**
- ❌ AnimationTree configuration in player scene
- ❌ StateMachine node hierarchy setup
- ❌ CameraRig integration
- ❌ Script attachment to player root

## Integration Steps

1. **Open `scenes/player.tscn` in Godot**

2. **Add AnimationTree to the visuals node:**
   - Select the `visuals` node
   - Add child node → AnimationTree
   - In AnimationTree properties:
     - Set "Tree Root" to a new AnimationNodeStateMachine
     - Set "Anim Player" path to `../meele-guy/AnimationPlayer`
     - Enable "Active"

3. **Configure the AnimationTree StateMachine:**
   - Open the AnimationTree editor (bottom panel)
   - Create animation states:
     - `idle` → Connect to "idle" animation from AnimationPlayer
     - `run` → Connect to "run" animation
     - `jumping` → Connect to "jumping" animation
   - Add transitions:
     - idle ↔ run (bidirectional)
     - idle → jumping
     - jumping → idle
     - run → jumping

4. **Attach Mannequiny script:**
   - Select the `visuals` node
   - In the Inspector, click the script icon and load `res://src/Player/Mannequiny.gd`
   - Verify the AnimationTree child node is detected

5. **Add StateMachine to Player:**
   - Select the root "Spatial" node (it's a KinematicBody)
   - Add child node → Node (name it "StateMachine")
   - Attach script: `res://src/Main/StateMachine/StateMachine.gd`
   - Under StateMachine, add child: Node named "Move"
   - Attach script to Move: `res://src/Player/States/Move.gd`
   - Under Move, add three child Nodes:
     - "Idle" → attach `res://src/Player/States/Idle.gd`
     - "Run" → attach `res://src/Player/States/Run.gd`
     - "Air" → attach `res://src/Player/States/Air.gd`
   - Select StateMachine, set "Initial State" to `Move/Idle`

6. **Add CameraRig:**
   - Select the root KinematicBody
   - Right-click → Instance Child Scene
   - Select `res://src/Player/Camera/CameraRig.tscn`
   - Position the CameraRig at approximately (0, 1.4, 0)
   - Verify CameraRig/InterpolatedCamera has "Current" checked

7. **Update Player script:**
   - Select the root node
   - Replace or update the script to `res://src/Player/Player.gd`
   - If keeping combat, merge functionality from original `scripts/player.gd`
   - The new script expects:
     ```gdscript
     onready var camera: CameraRig = $CameraRig
     onready var skin: Mannequiny = $visuals
     onready var state_machine: StateMachine = $StateMachine
     ```

8. **Disable old camera:**
   - Find the `camera_mount` node
   - Disable or remove it (the CameraRig replaces it)

9. **Test:**
   - Run the game
   - WASD should move the character
   - Mouse should control camera
   - Space should jump
   - Right-click should toggle aim

## Animation Mapping

The `Mannequiny.gd` script maps logical states to AnimationTree state names:

- IDLE → "idle"
- RUN → "run"
- AIR → "jumping"
- LAND → "idle" (slide-x doesn't have a dedicated land animation)

Modify these in `src/Player/Mannequiny.gd` if your AnimationTree uses different names.

## Adjusting Behavior

### Movement Parameters

Edit `src/Player/States/Move.gd`:
```gdscript
export var max_speed: = 12.0      # Maximum movement speed
export var move_speed: = 10.0     # Base movement speed
export var gravity = -80.0        # Gravity force
export var jump_impulse = 25      # Jump velocity
```

### Camera Settings

Edit `src/Player/Camera/States/Camera.gd`:
```gdscript
export var is_y_inverted: = false
export var fov_default: = 70.0
export var sensitivity_mouse: = Vector2(0.1, 0.1)
export var sensitivity_gamepad: = Vector2(2.5, 2.5)
```

### Camera Zoom

Edit `src/Player/Camera/SpringArm.gd`:
```gdscript
export var length_range: = Vector2(3.0, 6.0)  # Min and max camera distance
```

## Preserving Combat System

The original combat system (`scripts/player.gd.backup`) includes:
- Punch combos (regular → elbow → hard punch with dash)
- Kick combos (regular kicks → tornado kick with dash)
- Attack state management
- Dash mechanics

To integrate combat:

1. Create combat states extending `PlayerState`:
   - `Attack.gd` - Base attack state
   - `PunchCombo.gd` - Punch sequence state
   - `KickCombo.gd` - Kick sequence state

2. Add state transitions:
   - From Idle/Run → Attack states when attack inputs detected
   - From Attack → Idle when attack finishes

3. Port dash logic:
   - Copy dash mechanics from original player.gd
   - Integrate into attack states

Example attack state structure:
```gdscript
extends PlayerState

var attack_name: String
var dash_speed: float
var dash_duration: float

func enter(msg: = {}) -> void:
    is_attacking = true
    play_animation(attack_name)
    if dash_speed > 0:
        apply_dash()
    yield(animation_finished(), "completed")
    _state_machine.transition_to("Move/Idle")
```

## Troubleshooting

**Problem**: Camera not following player  
**Solution**: Ensure CameraRig script has `set_as_toplevel(true)` and InterpolatedCamera target is set correctly

**Problem**: Player not moving  
**Solution**: 
- Check input actions are defined in project.godot
- Verify StateMachine initial_state is "Move/Idle"
- Ensure player script has correct onready vars

**Problem**: Animations not playing  
**Solution**:
- AnimationTree must be active
- Verify AnimationTree has correct AnimationPlayer path
- Check AnimationTree state names match Mannequiny.gd

**Problem**: Character moves in wrong direction  
**Solution**: The movement is camera-relative. Ensure CameraRig is working and mouse input is captured

## Architecture Benefits

1. **Modularity**: States are self-contained and focused
2. **Maintainability**: Easy to add/remove/modify states
3. **Debuggability**: State transitions are explicit
4. **Extensibility**: Add new states without modifying existing ones
5. **Reusability**: State machine core works for any character/entity

## Next Steps

1. Complete the manual integration steps above
2. Test basic movement and camera
3. Integrate combat system from original player script
4. Add additional states as needed (dash, dodge, etc.)
5. Tune parameters for desired feel

## Notes

- All scripts are Godot 3.5 compatible
- The integration preserves slide-x's models, materials, and animations
- Level layout and environment are unchanged
- Original player script is backed up as `scripts/player.gd.backup`
