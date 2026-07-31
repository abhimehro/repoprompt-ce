#!/usr/bin/env python3
"""Extract the untrusted release-stage ZIP without allowing path traversal."""

from __future__ import annotations

import os
import shutil
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def confined(root: PurePosixPath, path: PurePosixPath) -> bool:
    return path == root or root in path.parents


def normalized_member(name: str) -> PurePosixPath:
    if "\\" in name:
        fail(f"staged archive member uses a backslash: {name}")
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        fail(f"staged archive member escapes extraction root: {name}")
    return path


def normalized_link_target(member: PurePosixPath, target: str) -> PurePosixPath:
    if "\\" in target:
        fail(f"staged archive symlink uses a backslash: {member}")
    raw = PurePosixPath(target)
    if raw.is_absolute():
        fail(f"staged archive symlink uses an absolute target: {member}")
    parts: list[str] = []
    for part in member.parent.joinpath(raw).parts:
        if part in {"", "."}:
            continue
        if part == "..":
            if not parts:
                fail(f"staged archive symlink escapes extraction root: {member}")
            parts.pop()
        else:
            parts.append(part)
    return PurePosixPath(*parts)


def allowed_symlink(member: PurePosixPath, target: str, app_name: str) -> bool:
    app = PurePosixPath(".build", "release", f"{app_name}.app")
    cli_links = {
        app / "Contents" / "Resources" / "repoprompt-mcp": "../MacOS/repoprompt-mcp",
        app / "Contents" / "Resources" / "bin" / "repoprompt-mcp": "../../MacOS/repoprompt-mcp",
    }
    sparkle = app / "Contents" / "Frameworks" / "Sparkle.framework"
    if member in cli_links:
        return target == cli_links[member]
    resolved = normalized_link_target(member, target)
    return confined(sparkle, member) and confined(sparkle, resolved)


def extract(archive: Path, destination: Path, app_name: str) -> None:
    if destination.exists():
        fail(f"staged extraction destination already exists: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    destination = destination.resolve()
    links: list[tuple[Path, str]] = []
    seen: set[PurePosixPath] = set()
    with zipfile.ZipFile(archive) as source:
        for info in source.infolist():
            member = normalized_member(info.filename.rstrip("/"))
            if member in seen:
                fail(f"duplicate staged archive member: {member}")
            seen.add(member)
            output = destination.joinpath(*member.parts)
            mode = info.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if info.is_dir() or kind == stat.S_IFDIR:
                output.mkdir(parents=True, exist_ok=True)
            elif kind == stat.S_IFLNK:
                target = source.read(info).decode("utf-8")
                if not allowed_symlink(member, target, app_name):
                    fail(f"unexpected or escaping staged archive symlink: {member} -> {target}")
                links.append((output, target))
            elif kind in {0, stat.S_IFREG}:
                output.parent.mkdir(parents=True, exist_ok=True)
                with source.open(info) as reader, output.open("wb") as writer:
                    shutil.copyfileobj(reader, writer)
                os.chmod(output, mode & 0o777)
            else:
                fail(f"unsupported staged archive member type: {member}")
    for output, target in links:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.symlink_to(target)


if len(sys.argv) != 4:
    fail("usage: extract_staged_release.py <archive> <destination> <app-name>")
extract(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
