# Trust Me, I'm an Engineer 🔧

A Game Jam game built in Godot 4.3 — repair objects using junk at a workbench!

## How to Play

### Controls
| Action | Input |
|---|---|
| Rotate assembly | Right Mouse Button drag (in table view) |
| Go under table / back | **Tab** key or the toggle button |
| Click a box (under table) | Left Mouse Button → grabs a random part |
| Place held part | Left Mouse Button (in table view) |
| Evaluate | Click "TRUST ME, I'M AN ENGINEER" |

### Gameplay Loop
1. Look at the **Repair Order** on the left — it tells you what tags are needed and where.
2. Hit **Tab** to look **under the table** — you'll see 3 junk boxes (A, B, C).
3. **Click a box** to grab a random part — camera auto-returns to table view.
4. **Move your mouse** over the workbench to position the part, then **Left Click** to drop it.
5. Repeat with more parts to build up the assembly.
6. Choose **Bolts** (rigid, permanent) or **Tape** (wobbly!) as your attachment method.
7. Hit **TRUST ME** to evaluate your score!

### Evaluation (Spatial Tags)
Each part carries tags (e.g. "blade", "motor", "frame"). The order specifies target positions in 3D space. The evaluator checks:
- Is a part with the required tag present?
- How close is it to the target position on the `AssemblyPivot`?
- Distance ≤ tolerance → full points. Further away → partial credit.

## Project Structure

```
trust_me_engineer/
├── project.godot          # Godot 4.3 project config + GameState autoload
├── icon.svg               # Project icon
├── scenes/
│   └── Main.tscn          # Root scene (script builds the 3D world in _ready)
├── scripts/
│   ├── GameState.gd       # Autoload singleton — global state & signals
│   ├── Main.gd            # Root scene controller (constructs world, handles input)
│   ├── CameraController.gd # Two-state camera (TABLE_VIEW / UNDER_TABLE_VIEW)
│   ├── JunkPart.gd        # RigidBody3D with tags, mouse-follow, placement
│   ├── JunkBox.gd         # Clickable storage box, randomizes part output
│   ├── AttachmentSystem.gd # Joint factory (PinJoint3D / Generic6DOFJoint3D)
│   └── EvaluationSystem.gd # Spatial-tag scoring against OrderData targets
└── data/
    ├── ItemData.gd         # Resource class: item_name, tags[], color, size, shape
    └── OrderData.gd        # Resource class: requirements[], tolerance
```

## Extending the Game

### Adding new parts
Edit `JunkBox.gd` → `_populate_pool()`. Add a dict with:
```gdscript
{"name": "My Part", "tags": ["my_tag"], "color": Color(r,g,b), "size": Vector3(w,h,d), "shape": "box"}
```
Shape types: `"box"`, `"cylinder"`, `"sphere"`

### Adding new orders
Create an `OrderData` resource in GDScript or via the editor. Set `requirements` array:
```gdscript
{
    "required_tag": "blade",
    "target_position": Vector3(0, 0.3, 0),  # Local to AssemblyPivot
    "points": 100
}
```

### Swapping the table
Replace the `CSGBox3D` named "Table" in `Main.gd → _build_table()` with your `table.glb`:
```gdscript
var table_scene = load("res://table.glb")
var table_inst = table_scene.instantiate()
add_child(table_inst)
```

## Architecture Notes

- The scene tree is built entirely in `Main.gd._ready()` — no complex `.tscn` serialization required.
- Physics layer assignments: Layer 1 = table, Layer 2 = parts, Layer 4 = boxes.
- `GameState` (autoload) holds the camera state, held part, active tool, and assembly registry.
- Joints are parented to `AssemblyPivot` so the whole assembly rotates together when the player drags RMB.
- `Generic6DOFJoint3D` with ±0.3 rad angular soft limits simulates the "tape" wobble.
