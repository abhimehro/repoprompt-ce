#!/usr/bin/env python3
"""Tests for Scripts/validate_json.py file validation and security checks."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
VALIDATE_JSON_PATH = SCRIPT_DIR / "validate_json.py"


class ValidateJSONTests(unittest.TestCase):
    def test_valid_json_file_succeeds(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            file_path = Path(tmp_dir) / "valid.json"
            file_path.write_text('{"key": "value"}\n', encoding="utf-8")
            result = subprocess.run(
                ["python3", str(VALIDATE_JSON_PATH), str(file_path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0)
            self.assertIn("Valid JSON", result.stdout)

    def test_invalid_json_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            file_path = Path(tmp_dir) / "invalid.json"
            file_path.write_text('{"key": }\n', encoding="utf-8")
            result = subprocess.run(
                ["python3", str(VALIDATE_JSON_PATH), str(file_path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("error: invalid JSON file", result.stderr)

    def test_symlink_file_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            target = Path(tmp_dir) / "target.json"
            target.write_text('{"key": "value"}\n', encoding="utf-8")
            link = Path(tmp_dir) / "link.json"
            link.symlink_to(target)
            result = subprocess.run(
                ["python3", str(VALIDATE_JSON_PATH), str(link)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("regular, non-symlink file", result.stderr)

    def test_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            result = subprocess.run(
                ["python3", str(VALIDATE_JSON_PATH), str(tmp_dir)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("regular, non-symlink file", result.stderr)

    def test_missing_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            missing = Path(tmp_dir) / "nonexistent.json"
            result = subprocess.run(
                ["python3", str(VALIDATE_JSON_PATH), str(missing)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("error: invalid JSON file", result.stderr)


if __name__ == "__main__":
    unittest.main()
