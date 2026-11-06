#!/usr/bin/env python3
"""Unit tests for extract_staged_release.py security boundary enforcement."""

import importlib.util
import os
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
MODULE_PATH = SCRIPT_DIR / "extract_staged_release.py"

SPEC = importlib.util.spec_from_file_location("extract_staged_release", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
extractor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(extractor)


class TestExtractStagedRelease(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.base_dir = Path(self.temp_dir.name)

    def create_zip(self, members: dict[str, bytes | str], symlinks: dict[str, str] | None = None) -> Path:
        zip_path = self.base_dir / "test.zip"
        with zipfile.ZipFile(zip_path, "w") as zf:
            for name, content in members.items():
                zf.writestr(name, content)
            if symlinks:
                for name, target in symlinks.items():
                    info = zipfile.ZipInfo(name)
                    info.external_attr = (stat.S_IFLNK | 0o777) << 16
                    zf.writestr(info, target)
        return zip_path

    def test_valid_extraction(self) -> None:
        zip_path = self.create_zip(
            members={"file.txt": b"hello world", "dir/nested.txt": b"nested"},
            symlinks={
                ".build/release/RepoPrompt.app/Contents/Resources/repoprompt-mcp": "../MacOS/repoprompt-mcp",
            },
        )
        dest = self.base_dir / "output"
        extractor.extract(zip_path, dest, "RepoPrompt")
        self.assertTrue((dest / "file.txt").exists())
        self.assertEqual((dest / "file.txt").read_bytes(), b"hello world")
        self.assertTrue((dest / "dir" / "nested.txt").exists())
        self.assertTrue((dest / ".build/release/RepoPrompt.app/Contents/Resources/repoprompt-mcp").is_symlink())

    def test_path_traversal_backslash_fails(self) -> None:
        zip_path = self.create_zip(members={"..\\escape.txt": b"bad"})
        dest = self.base_dir / "output"
        with self.assertRaises(SystemExit) as cm:
            extractor.extract(zip_path, dest, "RepoPrompt")
        self.assertIn("backslash", str(cm.exception))

    def test_path_traversal_parent_dir_fails(self) -> None:
        zip_path = self.create_zip(members={"../escape.txt": b"bad"})
        dest = self.base_dir / "output"
        with self.assertRaises(SystemExit) as cm:
            extractor.extract(zip_path, dest, "RepoPrompt")
        self.assertIn("escapes extraction root", str(cm.exception))

    def test_absolute_path_member_fails(self) -> None:
        zip_path = self.create_zip(members={"/etc/passwd": b"bad"})
        dest = self.base_dir / "output"
        with self.assertRaises(SystemExit) as cm:
            extractor.extract(zip_path, dest, "RepoPrompt")
        self.assertIn("escapes extraction root", str(cm.exception))

    def test_duplicate_member_fails(self) -> None:
        zip_path = self.base_dir / "duplicate.zip"
        with zipfile.ZipFile(zip_path, "w") as zf:
            zf.writestr("file.txt", b"first")
            zf.writestr("file.txt", b"second")
        dest = self.base_dir / "output"
        with self.assertRaises(SystemExit) as cm:
            extractor.extract(zip_path, dest, "RepoPrompt")
        self.assertIn("duplicate staged archive member", str(cm.exception))

    def test_unauthorized_relative_symlink_fails(self) -> None:
        zip_path = self.create_zip(
            members={"file.txt": b"data"},
            symlinks={"unauthorized_link": "file.txt"},
        )
        dest = self.base_dir / "output"
        with self.assertRaises(SystemExit) as cm:
            extractor.extract(zip_path, dest, "RepoPrompt")
        self.assertIn("unexpected or escaping staged archive symlink", str(cm.exception))

    def test_absolute_target_symlink_fails(self) -> None:
        zip_path = self.create_zip(
            members={"file.txt": b"data"},
            symlinks={"unauthorized_link": "/etc/passwd"},
        )
        dest = self.base_dir / "output"
        with self.assertRaises(SystemExit) as cm:
            extractor.extract(zip_path, dest, "RepoPrompt")
        self.assertIn("symlink uses an absolute target", str(cm.exception))


if __name__ == "__main__":
    unittest.main()
