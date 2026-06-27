import os
import re

files_to_check = [
    "scripts/GameState.gd",
    "scripts/AttachmentSystem.gd",
    "scripts/Main.gd",
    "scripts/EvaluationSystem.gd",
    "scripts/JunkPart.gd",
    "scripts/NailTool.gd",
    "scripts/TapeTool.gd"
]

for filepath in files_to_check:
    if not os.path.exists(filepath):
        continue
        
    with open(filepath, 'r') as f:
        content = f.read()

    # Revert 'is Node3D' back to 'is JunkPart'
    # EXCEPT for 'p is Node3D' in JunkPart.gd
    new_content = content.replace("is Node3D", "is JunkPart")
    new_content = new_content.replace("p is JunkPart", "p is Node3D")
    
    with open(filepath, 'w') as f:
        f.write(new_content)

print("is Node3D reverted to is JunkPart.")
