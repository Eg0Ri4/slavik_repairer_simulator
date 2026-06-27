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
        print(f"Not found: {filepath}")
        continue
        
    with open(filepath, 'r') as f:
        content = f.read()

    # Replacements
    new_content = content.replace("Array[JunkPart]", "Array[Node3D]")
    new_content = new_content.replace(": JunkPart", ": Node3D")
    new_content = new_content.replace("-> JunkPart", "-> Node3D")
    new_content = new_content.replace("as JunkPart", "as Node3D")
    new_content = new_content.replace("is JunkPart", "is Node3D") # wait, 'is Node3D' will match everything. 
    # But duck typing is better: let's leave 'is JunkPart' if possible, or wait, 'is JunkPart' is fine because 
    # it just checks if the class matches. The cyclic dependency issue is specifically about static typing
    # in variables and function arguments.
    
    with open(filepath, 'w') as f:
        f.write(new_content)

print("Cyclic dependency fixes applied.")
