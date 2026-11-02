"""Check source scale and prevent private contest materials from being tracked."""
from pathlib import Path
import subprocess
import re
import zipfile

root = Path(__file__).resolve().parents[1]
git = ["git", "-c", "core.quotepath=false", "-c", f"safe.directory={root.as_posix()}"]


def run(*args):
    return subprocess.check_output(git + list(args), cwd=root).decode("utf-8")


def check_name(name):
    parts = Path(name).parts
    forbidden = {"_local", ".local", "_build", ".mooncakes", ".venv", "__pycache__"}
    materials = re.search(r"申报|审查报告|辅助报告|汇总报告|(?:proposal|review|summary|ai)[_-]report", name, re.I)
    if forbidden.intersection(parts) or materials:
        raise SystemExit(f"Private/generated material is tracked: {name}")


tracked = run("ls-files", "-z").split("\0")
for name in filter(None, tracked):
    check_name(name)
for name in filter(None, run("log", "--all", "--format=", "--name-only").splitlines()):
    check_name(name)
commits = run("rev-list", "HEAD").splitlines()
if len(commits) <= 30:
    raise SystemExit("Expected more than 30 meaningful development commits")
for commit in commits:
    if not run("diff-tree", "--root", "--no-commit-id", "--name-only", "-r", commit).strip():
        raise SystemExit(f"Empty commit: {commit}")
counts = {"library": 0, "tests": 0, "examples": 0, "cli": 0}
for name in filter(None, tracked):
    if not name.endswith(".mbt"):
        continue
    category = "tests" if name.endswith("test.mbt") else (
        "examples" if name.startswith("examples/") else (
            "cli" if name.startswith("cmd/") else "library"
        )
    )
    counts[category] += sum(
        bool(line.strip()) and not line.lstrip().startswith("//")
        for line in (root / name).read_text(encoding="utf-8").splitlines()
    )
total = sum(counts.values())
print({**counts, "total_effective_moonbit_lines": total, "note": "library classification may include inline tests"})
if total <= 4000:
    raise SystemExit("Effective MoonBit source must exceed 4000 lines")
archives = list((root / "_build/publish").glob("*.zip"))
for archive in archives:
    with zipfile.ZipFile(archive) as package:
        for name in package.namelist():
            check_name(name)
print(f"{len(commits)} nonempty commits; tracked/history paths and {len(archives)} package ZIPs passed exclusions")
