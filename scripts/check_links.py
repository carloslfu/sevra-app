"""Repository-local Markdown link gate. dbmd separately validates wiki-links."""
import re
from pathlib import Path
root=Path(__file__).resolve().parent.parent
errors=[]
for directory in ["db","skills"]:
    files=list((root/directory).rglob("*.md"))
    if directory=="db":
        files += list(root.glob("*.md"))
    for file in files:
        text=file.read_text()
        for target in re.findall(r"\[[^\]\n]*\]\(([^)\s]+)\)",text):
            target=target.strip("<>").split("#")[0]
            if not target or ":" in target:
                continue
            if not (file.parent/target).exists():
                errors.append(f"{file.relative_to(root)}: missing {target}")
if errors:
    raise SystemExit("\n".join(errors))
print("Repository Markdown links: passed")
