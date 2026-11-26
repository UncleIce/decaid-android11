#!/usr/bin/env python3
"""Tests for check_shell_syntax.

Run with: python3 tool/ci/check_shell_syntax_test.py
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parent / "check_shell_syntax.py"
spec = importlib.util.spec_from_file_location("check_shell_syntax", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules["check_shell_syntax"] = module
spec.loader.exec_module(module)


VALID_WORKFLOW = """
name: fine
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: good step
        run: |
          echo one
          if true; then
            echo two
          fi
      - name: another
        run: echo plain
"""

STRAY_FI_WORKFLOW = """
name: broken
on: push
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - name: good
        run: echo fine
      - name: broken step
        run: |
          git push origin main
            echo done
          fi
"""

UNCLOSED_IF_WORKFLOW = """
name: broken
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - name: missing fi
        run: |
          if true; then
            echo yes
"""

BAD_YAML_WORKFLOW = """
name: broken
on: push
jobs:
   bad: [indentation
"""


class WorkflowDetectionTests(unittest.TestCase):
    def run_on(self, text: str) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "wf.yml"
            path.write_text(text, encoding="utf-8")
            return module.check_workflow(path)

    def test_valid_workflow_passes(self):
        self.assertEqual(self.run_on(VALID_WORKFLOW), [])

    def test_stray_fi_is_caught(self):
        # This is the exact shape that blocked the v0.9.3 release.
        problems = self.run_on(STRAY_FI_WORKFLOW)
        self.assertEqual(len(problems), 1)
        self.assertIn("syntax error", problems[0])
        self.assertIn("fi", problems[0])

    def test_unclosed_if_is_caught(self):
        problems = self.run_on(UNCLOSED_IF_WORKFLOW)
        self.assertEqual(len(problems), 1)
        self.assertIn("unexpected end of file", problems[0])

    def test_bad_yaml_is_caught(self):
        problems = self.run_on(BAD_YAML_WORKFLOW)
        self.assertEqual(len(problems), 1)
        self.assertIn("YAML does not parse", problems[0])

    def test_problem_path_points_at_the_step(self):
        problems = self.run_on(STRAY_FI_WORKFLOW)
        self.assertIn("jobs.sync.steps[1].run", problems[0])


class RunBlockDiscoveryTests(unittest.TestCase):
    def test_finds_nested_run_blocks(self):
        import yaml

        document = yaml.safe_load(VALID_WORKFLOW)
        found = list(module.iter_run_blocks(document))
        self.assertEqual(len(found), 2)
        self.assertTrue(any("steps[0]" in where for where, _ in found))

    def test_ignores_empty_run(self):
        import yaml

        document = yaml.safe_load(
            "jobs:\n  a:\n    steps:\n      - run: ''\n      - run: '   '\n"
        )
        self.assertEqual(list(module.iter_run_blocks(document)), [])


class ShellScriptTests(unittest.TestCase):
    def write_script(self, tmp: str, text: str, mode: int) -> Path:
        path = Path(tmp) / "script.sh"
        path.write_bytes(text.encode("utf-8"))
        path.chmod(mode)
        return path

    def test_clean_script_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_script(
                tmp, "#!/usr/bin/env bash\necho hi\n", 0o755
            )
            self.assertEqual(module.check_shell_script(path), [])

    def test_crlf_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_script(tmp, "#!/bin/bash\r\necho hi\r\n", 0o755)
            problems = module.check_shell_script(path)
            self.assertTrue(any("CRLF" in p for p in problems))

    def test_missing_shebang_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_script(tmp, "echo hi\n", 0o755)
            problems = module.check_shell_script(path)
            self.assertTrue(any("shebang" in p for p in problems))

    def test_non_executable_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_script(tmp, "#!/bin/bash\necho hi\n", 0o644)
            problems = module.check_shell_script(path)
            self.assertTrue(any("not executable" in p for p in problems))


class RepositoryTests(unittest.TestCase):
    def test_our_workflows_parse(self):
        # Guards the actual repo: any parse error here fails the suite.
        problems: list[str] = []
        for path in sorted(module.WORKFLOW_DIR.glob("*.y*ml")):
            problems.extend(module.check_workflow(path))
        self.assertEqual(problems, [], "\n".join(problems))


if __name__ == "__main__":
    unittest.main(verbosity=2)
