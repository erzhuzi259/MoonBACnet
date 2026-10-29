"""Read-only source/history and publication-content checks. Never pushes/publishes."""
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
git = ["git", "-c", f"safe.directory={root.as_posix()}"]
def run(*args):
    return subprocess.check_output(git + list(args), cwd=root).decode("utf-8")

files = list(filter(None, run("ls-files", "-z").split("\0")))
private = {"_local", "_build", ".git", ".mooncakes", "node_modules", "__pycache__"}
terms = ("申报书", "审查报告", "自查报告", "辅助报告", "汇总报告")
def clean(name):
    if set(name.replace("\\", "/").split("/")) & private or any(x in name for x in terms):
        raise SystemExit("Private/generated material found: " + name)

counts = dict(library=0, tests=0, examples=0, cli=0)
for name in files:
    clean(name)
    if name.endswith(".mbt"):
        kind = "tests" if name.endswith("test.mbt") else "examples" if name.startswith("examples/") else "cli" if name.startswith("cmd/") else "library"
        counts[kind] += sum(bool(x.strip()) and not x.lstrip().startswith("//")
                            for x in (root/name).read_text(encoding="utf-8-sig").splitlines())
commits = run("rev-list", "HEAD").splitlines()
for revision in commits:
    if not run("diff-tree", "--root", "--no-commit-id", "--name-only", "-r", revision).strip():
        raise SystemExit("Empty commit: " + revision)
total = sum(counts.values())
if total <= 4000 or len(commits) <= 30:
    raise SystemExit(f"Need >4000 effective MoonBit lines and >30 commits: {total}, {len(commits)}")
print({**counts, "effective_MoonBit_total": total, "nonempty_commits": len(commits)})
archives = list((root/"_build/publish").glob("*.zip"))
for archive in archives:
    with zipfile.ZipFile(archive) as package:
        for name in package.namelist():
            clean(name)
print(f"Tracked sources and {len(archives)} local package archive(s) passed hygiene checks; no upload")
