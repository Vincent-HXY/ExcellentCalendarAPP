#!/usr/bin/env python3
"""Collect a read-only manifest of a Git repository's uncommitted review scope.

The script never changes the index, worktree, configuration, or repository history.
It reports staged, unstaged, conflicted, renamed, deleted, and untracked paths,
plus likely governing documents and build/test manifests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable


STATUS_LABELS = {
    " ": "unmodified",
    "M": "modified",
    "T": "type-changed",
    "A": "added",
    "D": "deleted",
    "R": "renamed",
    "C": "copied",
    "U": "unmerged",
    "?": "untracked",
    "!": "ignored",
}

LANGUAGE_BY_SUFFIX = {
    ".c": "C",
    ".cc": "C++",
    ".cpp": "C++",
    ".cxx": "C++",
    ".h": "C/C++ header",
    ".hh": "C++ header",
    ".hpp": "C++ header",
    ".hxx": "C++ header",
    ".m": "Objective-C",
    ".mm": "Objective-C++",
    ".kt": "Kotlin",
    ".kts": "Kotlin script",
    ".java": "Java",
    ".swift": "Swift",
    ".rs": "Rust",
    ".go": "Go",
    ".py": "Python",
    ".pyi": "Python typing",
    ".js": "JavaScript",
    ".jsx": "JavaScript/JSX",
    ".ts": "TypeScript",
    ".tsx": "TypeScript/TSX",
    ".cs": "C#",
    ".fs": "F#",
    ".proto": "Protocol Buffers",
    ".thrift": "Thrift",
    ".sql": "SQL",
    ".graphql": "GraphQL",
    ".json": "JSON",
    ".yaml": "YAML",
    ".yml": "YAML",
    ".toml": "TOML",
    ".xml": "XML",
    ".gradle": "Gradle",
    ".cmake": "CMake",
    ".md": "Markdown",
    ".rst": "reStructuredText",
    ".sh": "Shell",
    ".bash": "Bash",
    ".zsh": "Zsh",
    ".ps1": "PowerShell",
}

SPECIAL_LANGUAGES = {
    "cmakelists.txt": "CMake",
    "makefile": "Make",
    "gnumakefile": "Make",
    "dockerfile": "Dockerfile",
    "meson.build": "Meson",
    "build": "Bazel",
    "build.bazel": "Bazel",
    "workspace": "Bazel",
    "workspace.bazel": "Bazel",
    "package.json": "Node package manifest",
    "cargo.toml": "Rust package manifest",
    "go.mod": "Go module manifest",
    "pyproject.toml": "Python project manifest",
    "pom.xml": "Maven",
}

DOC_BASENAMES = {
    "agents.md",
    "readme",
    "readme.md",
    "readme.rst",
    "architecture.md",
    "architecture.rst",
    "design.md",
    "contributing.md",
}

BUILD_TEST_BASENAMES = {
    "cmakelists.txt",
    "ctesttestfile.cmake",
    "makefile",
    "gnumakefile",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    "gradle.properties",
    "pom.xml",
    "cargo.toml",
    "go.mod",
    "pyproject.toml",
    "pytest.ini",
    "tox.ini",
    "setup.cfg",
    "package.json",
    "pnpm-workspace.yaml",
    "yarn.lock",
    "package-lock.json",
    "pnpm-lock.yaml",
    "meson.build",
    "meson_options.txt",
    "build",
    "build.bazel",
    "workspace",
    "workspace.bazel",
    "buck",
    "buckconfig",
}

CONFLICT_CODES = {"DD", "AU", "UD", "UA", "DU", "AA", "UU"}


class GitError(RuntimeError):
    pass


def decode_path(raw: bytes) -> str:
    return raw.decode("utf-8", errors="surrogateescape")


def run_git(
    cwd: Path,
    args: Iterable[str],
    *,
    check: bool = True,
    input_bytes: bytes | None = None,
) -> subprocess.CompletedProcess[bytes]:
    command = ["git", "-C", str(cwd), *args]
    try:
        result = subprocess.run(
            command,
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError as exc:
        raise GitError("git executable was not found") from exc

    if check and result.returncode != 0:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise GitError(f"{' '.join(command)} failed: {message or 'unknown git error'}")
    return result


def find_repo(start: Path) -> Path:
    result = run_git(start, ["rev-parse", "--show-toplevel"])
    return Path(decode_path(result.stdout).strip()).resolve()


def optional_git_text(root: Path, args: Iterable[str]) -> str | None:
    result = run_git(root, args, check=False)
    if result.returncode != 0:
        return None
    value = result.stdout.decode("utf-8", errors="replace").strip()
    return value or None


def resolve_baseline(root: Path) -> tuple[str, str | None, bool]:
    head = optional_git_text(root, ["rev-parse", "--verify", "HEAD"])
    if head:
        return "HEAD", head, False

    empty_tree_result = run_git(root, ["hash-object", "-t", "tree", "--stdin"], input_bytes=b"")
    empty_tree = empty_tree_result.stdout.decode("ascii", errors="strict").strip()
    return empty_tree, None, True


def language_for(path: str) -> str:
    name = Path(path).name.lower()
    if name in SPECIAL_LANGUAGES:
        return SPECIAL_LANGUAGES[name]
    return LANGUAGE_BY_SUFFIX.get(Path(path).suffix.lower(), "Unknown")


def parse_status(raw: bytes) -> list[dict[str, Any]]:
    tokens = raw.split(b"\0")
    entries: list[dict[str, Any]] = []
    index = 0

    while index < len(tokens):
        token = tokens[index]
        index += 1
        if not token:
            continue

        record = decode_path(token)
        if len(record) < 3:
            continue

        xy = record[:2]
        path = record[3:] if len(record) > 3 else ""
        original_path: str | None = None

        # With porcelain v1 -z, rename/copy records contain the destination in
        # the first record and the source path in the following NUL field.
        if (xy[0] in {"R", "C"} or xy[1] in {"R", "C"}) and index < len(tokens):
            if tokens[index]:
                original_path = decode_path(tokens[index])
                index += 1

        index_status = xy[0]
        worktree_status = xy[1]
        untracked = xy == "??"
        conflicted = xy in CONFLICT_CODES or "U" in xy
        staged = not untracked and index_status not in {" ", "?", "!"}
        unstaged = not untracked and worktree_status not in {" ", "?", "!"}

        entries.append(
            {
                "path": path,
                "original_path": original_path,
                "xy": xy,
                "index_status": STATUS_LABELS.get(index_status, index_status),
                "worktree_status": STATUS_LABELS.get(worktree_status, worktree_status),
                "staged": staged,
                "unstaged": unstaged,
                "untracked": untracked,
                "conflicted": conflicted,
                "language": language_for(path),
                "top_level": path.split("/", 1)[0] if path else "",
            }
        )

    return entries


def parse_numstat(raw: bytes) -> dict[str, dict[str, Any]]:
    """Parse `git diff --numstat -z` output, including rename records."""
    tokens = raw.split(b"\0")
    result: dict[str, dict[str, Any]] = {}
    index = 0

    while index < len(tokens):
        token = tokens[index]
        index += 1
        if not token:
            continue

        parts = token.split(b"\t", 2)
        if len(parts) != 3:
            continue

        added_raw, deleted_raw, path_raw = parts
        added: int | None = None if added_raw == b"-" else int(added_raw)
        deleted: int | None = None if deleted_raw == b"-" else int(deleted_raw)
        binary = added_raw == b"-" or deleted_raw == b"-"

        original_path: str | None = None
        if path_raw:
            path = decode_path(path_raw)
        else:
            # Rename/copy numstat record: header ends in a tab, then old and new
            # paths are emitted as separate NUL-delimited fields.
            if index + 1 >= len(tokens):
                break
            original_path = decode_path(tokens[index])
            path = decode_path(tokens[index + 1])
            index += 2

        result[path] = {
            "added_lines": added,
            "deleted_lines": deleted,
            "binary": binary,
            "numstat_original_path": original_path,
        }

    return result


def list_worktree_files(root: Path) -> list[str]:
    result = run_git(root, ["ls-files", "-co", "--exclude-standard", "-z"])
    return sorted({decode_path(item) for item in result.stdout.split(b"\0") if item})


def path_is_doc(path: str) -> bool:
    p = Path(path)
    name = p.name.lower()
    parts = {part.lower() for part in p.parts}
    return (
        name in DOC_BASENAMES
        or name.startswith("readme")
        or "architecture" in name
        or (p.suffix.lower() in {".md", ".rst"} and ("adr" in parts or "adrs" in parts))
    )


def path_is_build_or_test_manifest(path: str) -> bool:
    p = Path(path)
    name = p.name.lower()
    if name in BUILD_TEST_BASENAMES:
        return True
    if name.endswith(".gradle") or name.endswith(".gradle.kts"):
        return True
    if name.startswith("requirements") and p.suffix.lower() in {".txt", ".in"}:
        return True
    return False


def candidate_priority(path: str, changed_paths: set[str]) -> tuple[int, int, str]:
    p = Path(path)
    depth = len(p.parts)
    name = p.name.lower()

    if name == "agents.md":
        kind = 0
    elif name.startswith("readme"):
        kind = 1
    elif "architecture" in name or name == "design.md":
        kind = 2
    else:
        kind = 3

    proximity = 2
    parent = p.parent
    for changed in changed_paths:
        changed_parent = Path(changed).parent
        if parent == changed_parent:
            proximity = 0
            break
        try:
            changed_parent.relative_to(parent)
            proximity = min(proximity, 1)
        except ValueError:
            pass

    return (proximity, kind + depth, path)


def enrich_entries(root: Path, entries: list[dict[str, Any]], numstat: dict[str, dict[str, Any]]) -> None:
    for entry in entries:
        path = entry["path"]
        entry.update(
            numstat.get(
                path,
                {
                    "added_lines": None,
                    "deleted_lines": None,
                    "binary": None,
                    "numstat_original_path": None,
                },
            )
        )

        if entry["untracked"]:
            absolute = root / path
            try:
                entry["size_bytes"] = absolute.stat().st_size
            except OSError:
                entry["size_bytes"] = None
        else:
            entry["size_bytes"] = None


def build_manifest(repo_arg: Path) -> dict[str, Any]:
    root = find_repo(repo_arg)
    baseline, head, initial_repository = resolve_baseline(root)

    status_result = run_git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
    status_raw = status_result.stdout
    entries = parse_status(status_raw)

    numstat_result = run_git(root, ["diff", "--numstat", "-z", baseline, "--"])
    numstat = parse_numstat(numstat_result.stdout)
    enrich_entries(root, entries, numstat)

    changed_paths = {entry["path"] for entry in entries}
    all_files = list_worktree_files(root)
    docs = sorted(
        (path for path in all_files if path_is_doc(path)),
        key=lambda path: candidate_priority(path, changed_paths),
    )[:100]
    build_test = sorted(path for path in all_files if path_is_build_or_test_manifest(path))[:100]

    diff_check_result = run_git(root, ["diff", "--check", baseline, "--"], check=False)
    diff_check_output = (
        diff_check_result.stdout + diff_check_result.stderr
    ).decode("utf-8", errors="replace").strip()

    submodule_result = run_git(root, ["submodule", "status", "--recursive"], check=False)
    submodule_output = submodule_result.stdout.decode("utf-8", errors="replace").strip()

    counts = {
        "total_paths": len(entries),
        "staged_paths": sum(bool(entry["staged"]) for entry in entries),
        "unstaged_paths": sum(bool(entry["unstaged"]) for entry in entries),
        "untracked_paths": sum(bool(entry["untracked"]) for entry in entries),
        "conflicted_paths": sum(bool(entry["conflicted"]) for entry in entries),
        "renamed_or_copied_paths": sum(bool(entry["original_path"]) for entry in entries),
        "deleted_paths": sum("D" in entry["xy"] for entry in entries),
        "binary_tracked_paths": sum(entry["binary"] is True for entry in entries),
    }

    branch = optional_git_text(root, ["symbolic-ref", "--short", "-q", "HEAD"])
    upstream = optional_git_text(
        root,
        ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
    )

    return {
        "schema_version": 1,
        "read_only": True,
        "repository_root": str(root),
        "branch": branch,
        "upstream": upstream,
        "head": head,
        "baseline": baseline,
        "initial_repository": initial_repository,
        "status_sha256": hashlib.sha256(status_raw).hexdigest(),
        "counts": counts,
        "changes": sorted(entries, key=lambda entry: entry["path"]),
        "governing_document_candidates": docs,
        "build_and_test_manifest_candidates": build_test,
        "diff_check": {
            "exit_code": diff_check_result.returncode,
            "output": diff_check_output,
        },
        "submodule_status": submodule_output.splitlines() if submodule_output else [],
        "recommended_combined_diff_command": f"git diff --no-ext-diff --find-renames {baseline} --",
        "recommended_staged_diff_command": f"git diff --cached --no-ext-diff --find-renames {baseline} --",
        "recommended_unstaged_diff_command": "git diff --no-ext-diff --find-renames --",
    }


def render_text(manifest: dict[str, Any]) -> str:
    lines = [
        f"Repository: {manifest['repository_root']}",
        f"Branch: {manifest['branch'] or '(detached/unknown)'}",
        f"HEAD: {manifest['head'] or '(no commits)'}",
        f"Baseline: {manifest['baseline']}",
        f"Initial repository: {manifest['initial_repository']}",
        f"Status SHA-256: {manifest['status_sha256']}",
        "Counts: " + ", ".join(f"{key}={value}" for key, value in manifest["counts"].items()),
        "",
        "Changes:",
    ]

    if not manifest["changes"]:
        lines.append("  (none)")
    else:
        for entry in manifest["changes"]:
            rename = f" <- {entry['original_path']}" if entry["original_path"] else ""
            stat = ""
            if entry["added_lines"] is not None or entry["deleted_lines"] is not None:
                stat = f" +{entry['added_lines']} -{entry['deleted_lines']}"
            elif entry["binary"]:
                stat = " [binary]"
            lines.append(
                f"  {entry['xy']} {entry['path']}{rename} [{entry['language']}]{stat}"
            )

    lines.extend(["", "Governing document candidates:"])
    lines.extend(f"  {path}" for path in manifest["governing_document_candidates"] or ["(none)"])

    lines.extend(["", "Build/test manifest candidates:"])
    lines.extend(f"  {path}" for path in manifest["build_and_test_manifest_candidates"] or ["(none)"])

    lines.extend(["", f"git diff --check exit: {manifest['diff_check']['exit_code']}"])
    if manifest["diff_check"]["output"]:
        lines.append(manifest["diff_check"]["output"])

    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect a read-only manifest of staged, unstaged, and untracked Git changes."
    )
    parser.add_argument(
        "--repo",
        default=".",
        help="Path inside the Git repository (default: current directory).",
    )
    parser.add_argument(
        "--format",
        choices=("json", "text"),
        default="json",
        help="Output format (default: json).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        manifest = build_manifest(Path(os.path.expanduser(args.repo)).resolve())
    except (GitError, OSError, ValueError) as exc:
        print(f"collect_review_scope: {exc}", file=sys.stderr)
        return 2

    if args.format == "json":
        json.dump(manifest, sys.stdout, indent=2, ensure_ascii=True)
        sys.stdout.write("\n")
    else:
        print(render_text(manifest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
