#!/usr/bin/env python3
"""Check every shell script embedded in our workflow files.

GitHub Actions runs each `run:` block through bash without ever parsing it
ahead of time, so a stray `fi` or a missing `done` only shows up when the
job actually fires. On a schedule that can be days later, and when it is
the sync workflow the failure silently blocks releases.

This walks every `run:` scalar in .github/workflows/*.yml, writes it to a
temp file and asks `bash -n` whether it parses. Nothing is executed.

Also checks standalone .sh files for interpreter, line endings and the
executable bit, which have each broken CI here at least once.
"""

from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("pyyaml is required: pip install pyyaml")

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_DIR = ROOT / ".github" / "workflows"

# Directories that hold upstream code and are not ours to police.
SKIP_DIRS = {".git", "build", "node_modules", ".dart_tool", "plugins_tmp"}


def iter_run_blocks(node, path="root"):
    """Yield (path, script) for every non-empty `run:` string in the tree."""
    if isinstance(node, dict):
        for key, value in node.items():
            child = f"{path}.{key}"
            if key == "run" and isinstance(value, str) and value.strip():
                yield child, value
            else:
                yield from iter_run_blocks(value, child)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from iter_run_blocks(value, f"{path}[{index}]")


def check_bash(script: str) -> str | None:
    """Return an error string when bash cannot parse the script."""
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as handle:
        handle.write(script)
        name = handle.name
    try:
        result = subprocess.run(
            ["bash", "-n", name], capture_output=True, text=True
        )
        if result.returncode == 0:
            return None
        # The temp path is noise; report the message only.
        message = result.stderr.replace(name, "<run block>").strip()
        return message or "bash -n failed"
    finally:
        os.unlink(name)


def check_workflow(path: Path) -> list[str]:
    problems: list[str] = []
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as error:
        return [f"{path.name}: YAML does not parse -- {error}"]

    count = 0
    for where, script in iter_run_blocks(document):
        count += 1
        error = check_bash(script)
        if error:
            problems.append(f"{path.name} [{where}]: {error}")

    print(f"  {path.name}: {count} run block(s)")
    return problems


def display_path(path: Path) -> str:
    """Path relative to the repo root, falling back to the absolute path."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def check_shell_script(path: Path) -> list[str]:
    problems: list[str] = []
    relative = display_path(path)
    raw = path.read_bytes()

    if b"\r\n" in raw:
        # With CRLF the kernel looks for an interpreter named "bash\r".
        problems.append(
            f"{relative}: CRLF line endings (add to .gitattributes as text eol=lf)"
        )

    text = raw.decode("utf-8", errors="replace")
    if not text.startswith("#!"):
        problems.append(f"{relative}: missing shebang")
    elif "bash" not in text.splitlines()[0]:
        problems.append(f"{relative}: shebang is not bash")

    if not path.stat().st_mode & stat.S_IXUSR:
        problems.append(f"{relative}: not executable (chmod +x)")

    result = subprocess.run(
        ["bash", "-n", str(path)], capture_output=True, text=True
    )
    if result.returncode != 0:
        problems.append(f"{relative}: {result.stderr.strip()}")

    return problems


def main() -> int:
    if not WORKFLOW_DIR.is_dir():
        return 0

    print("Workflow run blocks")
    problems: list[str] = []
    for path in sorted(WORKFLOW_DIR.glob("*.y*ml")):
        problems.extend(check_workflow(path))

    scripts = sorted(
        path
        for path in ROOT.rglob("*.sh")
        if not any(part in SKIP_DIRS for part in path.parts)
    )
    if scripts:
        print("\nStandalone shell scripts")
    for path in scripts:
        print(f"  {path.relative_to(ROOT)}")
        problems.extend(check_shell_script(path))

    print()
    if problems:
        print("FAILED")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("OK: all shell code parses")
    return 0


if __name__ == "__main__":
    sys.exit(main())
