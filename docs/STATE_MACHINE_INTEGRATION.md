# State Machine Integration Guide for slide-x

> **✅ Integration Complete!** The third-person character controller has been fully integrated into slide-x.
> This document now serves as a reference for the completed integration and testing guide.

## Integration Status

**All integration steps have been completed:**
- ✅ AnimationTree configuration in player scene
- ✅ StateMachine node hierarchy setup (Move → Idle, Run, Air)
- ✅ CameraRig integration with SpringArm and InterpolatedCamera
- ✅ Script attachments to player root and all nodes
- ✅ Input action mappings (move_front/back/left/right, toggle_aim, fire, zoom_in/zoom_out)
- ✅ Fixed node name typo (StateMachine)
- ✅ Legacy player script moved to backup (scripts/player.gd.old-legacy)

## Quick Reference

For detailed information on:
- **Architecture overview** → See [third_person_controller.md](third_person_controller.md#architecture-overview)
- **Tweaking movement/camera** → See [third_person_controller.md](third_person_controller.md#tweaking-movement-behavior)
- **Animation mapping** → See [third_person_controller.md](third_person_controller.md#animation-mapping)
- **Extending the system** → See [third_person_controller.md](third_person_controller.md#extending-the-system)

## Testing the Integration

To verify the third-person controller is working correctly:

1. **Open the project in Godot 3.5**
   ```bash
   godot project.godot
   ```

2. **Run the main scene** (F5 or Play button)
   - The game should start with the player in the main scene
   - Mouse should be captured (hidden cursor)

3. **Test basic movement:**
   - **W/A/S/D**: Move character (camera-relative direction)
   - **Mouse**: Rotate camera around character
   - **Space**: Jump
   - Character should smoothly transition between idle → run → air states
   - Character should face the direction of movement

4. **Test camera controls:**
   - **Right Mouse Button**: Toggle aim mode
     - Camera should zoom in and offset to shoulder view
     - Aim reticle should appear
   - **Mouse Wheel Up/Down**: Zoom camera in/out
   - Camera should smoothly follow the character
   - Camera should not clip through walls (SpringArm collision)

5. **Test animations:**
   - Standing still: "idle" animation should play
   - Moving: "run" animation should play
   - Jumping: "jumping" animation should play
   - Animations should transition smoothly

6. **Verify no console errors:**
   - Check the Output panel in Godot
   - There should be no errors related to missing nodes or scripts
   - State transitions should log cleanly (if debug enabled)

## Current Scene Structure

The player scene (`scenes/player.tscn`) is now fully configured with:

```
Spatial (KinematicBody) - Root node with Player.gd script
├── CollisionShape - Player collision
├── visuals (Spatial) - Visual container with Mannequiny.gd script
│   ├── meele-guy - Character model
│   │   ├── Armature/Skeleton - Character skeleton
│   │   └── AnimationPlayer - Character animations
│   └── AnimationTree - State machine for animations
│       └── States: idle, run, jumping, walk, etc.
├── camera_mount (hidden) - Legacy camera (disabled)
├── StateMachine - Player state machine
│   └── Move - Movement parent state with Move.gd
│       ├── Idle - Idle state with Idle.gd
│       ├── Run - Running state with Run.gd
│       └── Air - Jumping/falling state with Air.gd
└── CameraRig - Camera system
    ├── InterpolatedCamera - Smooth camera following
    │   └── AimRay - Raycast for aiming
    ├── SpringArm - Collision-aware camera arm
    │   └── CameraTarget - Camera position target
    ├── AimTarget - Visual aim reticle
    └── StateMachine - Camera state machine
        └── Camera - Parent camera state
            ├── Default - Normal third-person view
            └── Aim - Aim mode view
```

## Input Mapping

The following input actions have been configured in `project.godot`:

**Movement:**
- `move_front` (W) - Move forward relative to camera
- `move_back` (S) - Move backward relative to camera  
- `move_left` (A) - Move left relative to camera
- `move_right` (D) - Move right relative to camera
- `jump` (Space) - Jump

**Camera:**
- `toggle_aim` (Right Mouse Button) - Toggle aim mode
- `fire` (Left Mouse Button) - Fire/confirm in aim mode
- `zoom_in` (Mouse Wheel Up) - Zoom camera in
- `zoom_out` (Mouse Wheel Down) - Zoom camera out

**Legacy Combat (preserved for future use):**
- `run` (Shift) - Sprint toggle
- `punch` (I) - Punch combos
- `kick` (O) - Kick combos
- `elbow` (P) - Elbow attack

## Animation Mapping

The `Mannequiny.gd` script maps logical states to AnimationTree states:

| Logical State | AnimationTree State | Description |
|--------------|-------------------|-------------|
| States.IDLE | "idle" | Character standing still |
| States.RUN | "run" | Character moving |
| States.AIR | "jumping" | Character in air (jump/fall) |
| States.LAND | "idle" | Landing animation (uses idle) |

The AnimationTree includes additional animations for future combat integration:
- walk, kick, punch, punch-elbow, punch-hard, kick-tornado, jump-back, strafe variations

## Differences from 3d-character-testing

slide-x maintains compatibility with the original 3d-character-testing architecture with these adaptations:

1. **Model**: Uses melee-guy character instead of mannequin
2. **Animations**: Maps to slide-x's existing animations (idle, run, jumping, etc.)
3. **Combat System**: Legacy combat from scripts/player.gd.old-legacy preserved for future state-based integration
4. **Scene Structure**: visuals node contains both model and AnimationTree
5. **Input Actions**: Uses move_front/back/left/right instead of ui_up/down/left/right for better clarity

## Known Limitations

1. **No walk/run speed blending**: Currently only uses "run" animation for all movement speeds. The "walk" animation exists but is not integrated with a blend space.
2. **Combat not integrated**: Legacy combat system (punches, kicks, combos) is preserved in scripts/player.gd.old-legacy but not yet integrated into the state machine.
3. **No strafe animations**: Strafe animations exist in AnimationPlayer but are not wired to strafing movement.
4. **Simple landing**: Uses "idle" animation for landing instead of a dedicated landing animation transition.

## Future Enhancements

To fully match 3d-character-testing functionality and add slide-x specific features:

1. **Add Combat States**:
   - Create Attack.gd, Punch.gd, Kick.gd states extending PlayerState
   - Port dash mechanics from scripts/player.gd.old-legacy
   - Integrate combo system into state transitions
   - Add attack animations to Mannequiny state mapping

2. **Improve Animation System**:
   - Create BlendSpace2D for walk/run speed blending
   - Wire strafe animations to lateral movement
   - Add dedicated landing animation state
   - Consider adding animation smoothing/crossfading

3. **Enhance Camera**:
   - Add combat camera mode with wider FOV
   - Implement camera shake for impacts
   - Add cinematic camera angles for special attacks

4. **Extend Movement**:
   - Add dodge/roll state with invincibility frames
   - Implement wall-running or climbing states
   - Add ledge grabbing detection

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

## Troubleshooting

**Problem**: Camera not following player  
**Solution**: CameraRig has `set_as_toplevel(true)` and InterpolatedCamera target is correctly set to SpringArm/CameraTarget

**Problem**: Player not moving  
**Solution**: 
- Input actions are defined in project.godot (move_front/back/left/right)
- StateMachine initial_state is set to "Move/Idle"
- Player.gd has correct onready references to camera, skin, state_machine

**Problem**: Animations not playing  
**Solution**:
- AnimationTree is active (checked in inspector)
- AnimationTree has correct AnimationPlayer path (../meele-guy/AnimationPlayer)
- AnimationTree state names match Mannequiny.gd transitions

**Problem**: Character moves in wrong direction  
**Solution**: Movement is camera-relative. CameraRig must be working and mouse input captured

**Problem**: Mouse cursor visible/not captured
**Solution**: Player.gd calls `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)` in _ready()

## References

- Main documentation: [third_person_controller.md](third_person_controller.md)
- Original implementation: [Lumexio/3d-character-testing](https://github.com/Lumexio/3d-character-testing)
- Godot 3.5 docs: [docs.godotengine.org/en/3.5](https://docs.godotengine.org/en/3.5/)
