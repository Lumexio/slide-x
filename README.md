# slide-x

A Godot 3.5 third-person action game with a state-machine-based character controller.

## Features

- Third-person camera with aim mode
- State-machine-based player controller
- Combat system with punch and kick combos
- Dynamic camera following with spring arm
- Jump and double-jump mechanics

## New: State Machine Architecture

This project now includes a fully integrated modular state-machine-based character controller ported from [3d-character-testing](https://github.com/Lumexio/3d-character-testing).

### Key Components

- **State Machine Core**: Reusable hierarchical state machine system
- **Player States**: Idle, Run, Air (jump/fall) states with camera-relative movement
- **Camera Rig**: Spring arm camera with aiming mode, zoom, and auto-rotation
- **Animation Controller**: Mannequiny script for managing AnimationTree transitions

### Getting Started

The third-person character controller is fully integrated and ready to use:

📖 **[Third-Person Controller Documentation](docs/third_person_controller.md)** - Architecture and usage guide
⚙️ **[Integration Status](docs/STATE_MACHINE_INTEGRATION.md)** - Scene structure and testing guide

The documentation covers:

- Complete architecture overview and component descriptions
- How to tweak movement and camera behavior
- Animation mapping to kinetic-chad model
- Input configuration reference
- Extending the system with new states
- Troubleshooting common issues

### Controls

**Movement:**

- WASD: Move character (camera-relative)
- Mouse: Rotate camera
- Space: Jump
- Shift: Run (original system)

**Camera:**

- Right Mouse Button: Toggle aim mode
- Left Mouse Button: Fire/confirm (in aim mode)
- Mouse Wheel: Zoom in/out

**Combat** (original system):

- I: Punch combos
- O: Kick combos
- P: Elbow attack

## Development

This is a Godot 3.5 project. Open `project.godot` in Godot 3.5+ to edit.

### Project Structure

```
slide-x/
├── src/
│   ├── Main/
│   │   └── StateMachine/        # Core state machine system
│   └── Player/
│       ├── Camera/               # Camera rig and states
│       ├── States/               # Player movement states
│       ├── Player.gd             # Main player controller
│       ├── PlayerState.gd        # Base player state
│       └── Mannequiny.gd         # Animation controller
├── scenes/
│   ├── main.tscn                 # Main game scene
│   └── player.tscn               # Player character scene
├── scripts/
│   ├── player.gd.old-legacy       # Original player script (backup)
│   └── player.gd.backup           # Backup of original script
├── assets/                       # Models, textures, animations
└── docs/
    └── STATE_MACHINE_INTEGRATION.md  # Integration guide
```

## Contributing

When making changes to the player controller or adding new states:

1. Extend the appropriate base class (`PlayerState` for player, `CameraState` for camera)
2. Override relevant callbacks (`enter`, `exit`, `physics_process`, etc.)
3. Add state transitions as needed
4. Update documentation if adding new features

## License

[Add your license information here]
