#!/usr/bin/env python3
"""Resolve git merge conflicts and post-merge build/test failures via an OpenAI-compatible API."""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Any

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTECTED_PREFIXES = (".git/", ".github/", ".build/", "build/")
CONFLICT_MARKER_RE = re.compile(r"^(<{7} |>{7} |\={7}$)", re.MULTILINE)
ALLOWED_GIT_SUBCOMMANDS = {"diff", "log", "show", "status", "grep"}


def chat_completions_url(base_url: str) -> str:
    """Normalize an OpenAI-compatible base URL into a /chat/completions endpoint."""
    cleaned = base_url.strip().rstrip("/")
    if not cleaned:
        raise ValueError("LLM_BASE_URL is empty")
    if cleaned.endswith("/chat/completions"):
        return cleaned
    return f"{cleaned}/chat/completions"


def resolve_repo_path(relative_path: str, *, allow_protected_read: bool = False) -> pathlib.Path:
    """Resolve a relative path inside the repository root, blocking traversal and protected writes."""
    if not relative_path or pathlib.Path(relative_path).is_absolute():
        raise ValueError(f"Path must be relative to repository root: {relative_path!r}")
    candidate = (REPO_ROOT / relative_path).resolve()
    try:
        rel = candidate.relative_to(REPO_ROOT)
    except ValueError as exc:
        raise ValueError(f"Path escapes repository root: {relative_path!r}") from exc
    posix_rel = rel.as_posix()
    if not allow_protected_read and any(
        posix_rel == prefix.rstrip("/") or posix_rel.startswith(prefix)
        for prefix in PROTECTED_PREFIXES
    ):
        raise ValueError(f"Modifying protected path is not allowed: {posix_rel}")
    return candidate


def run_cmd(cmd: list[str], *, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    """Run a subprocess in REPO_ROOT and capture text output."""
    return subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def tail_output(proc: subprocess.CompletedProcess[str], max_lines: int = 160) -> str:
    """Format return code and trailing stdout/stderr lines for compact LLM inspection."""
    combined = "\n".join(part for part in (proc.stdout.strip(), proc.stderr.strip()) if part)
    lines = combined.splitlines()
    if len(lines) > max_lines:
        lines = ["...(truncated)..."] + lines[-max_lines:]
    body = "\n".join(lines) if lines else "(no output)"
    return f"exit_code={proc.returncode}\n{body}"


def unmerged_files() -> list[str]:
    """Return tracked paths still in an unmerged git state."""
    proc = run_cmd(["git", "diff", "--name-only", "--diff-filter=U"])
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def files_with_conflict_markers(paths: list[str]) -> list[str]:
    """Check specified or git-dirty files for leftover merge conflict markers."""
    if not paths:
        proc = run_cmd(["git", "status", "--porcelain"])
        candidates = []
        for line in proc.stdout.splitlines():
            if len(line) > 3:
                path_part = line[3:].split(" -> ")[-1].strip().strip('"')
                if path_part:
                    candidates.append(path_part)
        paths = candidates

    flagged: list[str] = []
    for rel in sorted(set(paths)):
        full = REPO_ROOT / rel
        if not full.is_file():
            continue
        try:
            text = full.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if "<<<<<<< " in text and ">>>>>>> " in text and CONFLICT_MARKER_RE.search(text):
            flagged.append(rel)
    return flagged


class MergeResolverWorkspace:
    """Stateful tool executor scoped strictly to the WonderBox repository."""

    def __init__(self) -> None:
        self.modified_files: set[str] = set()
        self.tests_passed_since_edit = False
        self.finished_summary: str | None = None

    def tool_schemas(self) -> list[dict[str, Any]]:
        return [
            {
                "type": "function",
                "function": {
                    "name": "list_repo_status",
                    "description": "Show git status --short, unmerged conflict files, and diff --stat.",
                    "parameters": {"type": "object", "properties": {}, "required": []},
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "read_file",
                    "description": "Read a UTF-8 file from the repository with 1-based line numbers.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string", "description": "Relative file path."},
                            "start_line": {"type": "integer", "description": "1-based start line (default 1)."},
                            "end_line": {"type": "integer", "description": "1-based inclusive end line (default 250)."},
                        },
                        "required": ["path"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "search_repo",
                    "description": "Search text across repository sources and tests (excluding .git/.build/build).",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "pattern": {"type": "string", "description": "Text or regex pattern."},
                            "path": {"type": "string", "description": "Optional relative directory/file (default '.')."},
                        },
                        "required": ["pattern"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "replace_in_file",
                    "description": "Replace an exact unique substring in a repository file.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string", "description": "Relative file path."},
                            "old_text": {"type": "string", "description": "Exact existing text (must match once)."},
                            "new_text": {"type": "string", "description": "Replacement text."},
                        },
                        "required": ["path", "old_text", "new_text"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "write_file",
                    "description": "Overwrite a file in the repository with complete content.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string", "description": "Relative file path."},
                            "content": {"type": "string", "description": "Complete file contents."},
                        },
                        "required": ["path", "content"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "git_inspect",
                    "description": "Run a read-only git subcommand (diff, log, show, status, grep).",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "subcommand": {"type": "string", "enum": sorted(ALLOWED_GIT_SUBCOMMANDS)},
                            "args": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Additional arguments passed to git subcommand.",
                            },
                        },
                        "required": ["subcommand"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "run_tests",
                    "description": "Run swift test and/or Python packaging tests to verify the merge.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "scope": {
                                "type": "string",
                                "enum": ["all", "swift", "packaging"],
                                "description": "Which test suite to run (default 'all').",
                            }
                        },
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "finish",
                    "description": "Call once all conflicts are resolved and run_tests(scope='all') has passed.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "summary": {"type": "string", "description": "Concise summary of resolved conflicts/fixes."},
                        },
                        "required": ["summary"],
                    },
                },
            },
        ]

    def execute(self, name: str, args: dict[str, Any]) -> str:
        try:
            handler = getattr(self, f"_tool_{name}", None)
            if handler is None:
                return f"Error: unknown tool {name!r}"
            return handler(args)
        except Exception as exc:  # noqa: BLE001 - return tool errors cleanly to model
            return f"Error: {exc}"

    def _tool_list_repo_status(self, _args: dict[str, Any]) -> str:
        status = run_cmd(["git", "status", "--short"]).stdout.strip()
        unmerged = unmerged_files()
        diff_stat = run_cmd(["git", "diff", "--stat"]).stdout.strip()
        return json.dumps(
            {
                "unmerged_files": unmerged,
                "status_short": status.splitlines(),
                "diff_stat": diff_stat.splitlines(),
            },
            ensure_ascii=False,
            indent=2,
        )

    def _tool_read_file(self, args: dict[str, Any]) -> str:
        path = resolve_repo_path(str(args["path"]), allow_protected_read=True)
        if not path.is_file():
            raise FileNotFoundError(f"File not found: {args['path']}")
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        start = max(1, int(args.get("start_line", 1)))
        end = min(len(lines), max(start, int(args.get("end_line", start + 249))))
        if end - start + 1 > 400:
            end = start + 399
        rendered = [f"{idx}: {lines[idx - 1]}" for idx in range(start, end + 1)]
        header = f"Showing lines {start}-{end} of {len(lines)} ({args['path']}):\n"
        return header + "\n".join(rendered)

    def _tool_search_repo(self, args: dict[str, Any]) -> str:
        pattern = str(args["pattern"])
        rel = str(args.get("path", "."))
        target = resolve_repo_path(rel, allow_protected_read=True) if rel != "." else REPO_ROOT
        try:
            proc = run_cmd(
                [
                    "rg",
                    "-n",
                    "--no-heading",
                    "--max-count",
                    "80",
                    "--glob",
                    "!.git/**",
                    "--glob",
                    "!.build/**",
                    "--glob",
                    "!build/**",
                    pattern,
                    str(target),
                ],
                timeout=30,
            )
            if proc.returncode not in (0, 1):
                raise RuntimeError(tail_output(proc, max_lines=40))
            lines = proc.stdout.splitlines()[:80]
            return "\n".join(lines) if lines else "(no matches)"
        except FileNotFoundError:
            regex = re.compile(pattern)
            matches: list[str] = []
            files = [target] if target.is_file() else sorted(target.rglob("*"))
            for item in files:
                if not item.is_file():
                    continue
                rel_item = item.relative_to(REPO_ROOT).as_posix()
                if any(rel_item.startswith(prefix) for prefix in PROTECTED_PREFIXES):
                    continue
                try:
                    for idx, line in enumerate(item.read_text(encoding="utf-8").splitlines(), start=1):
                        if regex.search(line):
                            matches.append(f"{rel_item}:{idx}: {line}")
                            if len(matches) >= 80:
                                return "\n".join(matches)
                except UnicodeDecodeError:
                    continue
            return "\n".join(matches) if matches else "(no matches)"

    def _mark_edited(self, rel_path: str) -> None:
        self.modified_files.add(rel_path)
        self.tests_passed_since_edit = False
        # Stage resolved file immediately so git unmerged index clears once resolved cleanly.
        run_cmd(["git", "add", "--", rel_path])

    def _tool_replace_in_file(self, args: dict[str, Any]) -> str:
        rel = str(args["path"])
        target = resolve_repo_path(rel)
        old_text = str(args["old_text"])
        new_text = str(args["new_text"])
        if not target.is_file():
            raise FileNotFoundError(f"File not found: {rel}")
        text = target.read_text(encoding="utf-8")
        occurrences = text.count(old_text)
        if occurrences == 0:
            raise ValueError(f"old_text not found in {rel}")
        if occurrences > 1:
            raise ValueError(f"old_text matched {occurrences} times in {rel}; provide more surrounding context")
        target.write_text(text.replace(old_text, new_text, 1), encoding="utf-8")
        self._mark_edited(rel)
        return f"Updated {rel} (1 replacement applied)."

    def _tool_write_file(self, args: dict[str, Any]) -> str:
        rel = str(args["path"])
        target = resolve_repo_path(rel)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(str(args["content"]), encoding="utf-8")
        self._mark_edited(rel)
        return f"Wrote {rel}."

    def _tool_git_inspect(self, args: dict[str, Any]) -> str:
        sub = str(args["subcommand"])
        if sub not in ALLOWED_GIT_SUBCOMMANDS:
            raise ValueError(f"Unsupported git subcommand: {sub}")
        extra = [str(item) for item in args.get("args", [])]
        proc = run_cmd(["git", sub, *extra], timeout=30)
        return tail_output(proc, max_lines=160)

    def _tool_run_tests(self, args: dict[str, Any]) -> str:
        scope = str(args.get("scope", "all"))
        if scope not in {"all", "swift", "packaging"}:
            raise ValueError(f"Invalid scope: {scope}")
        outputs: list[str] = []
        swift_ok = True
        pkg_ok = True

        if scope in {"all", "swift"}:
            swift_proc = run_cmd(["swift", "test"], timeout=600)
            swift_ok = swift_proc.returncode == 0
            outputs.append("[swift test]\n" + tail_output(swift_proc, max_lines=120))

        if scope in {"all", "packaging"}:
            pkg_proc = run_cmd(["python3", "-m", "unittest", "discover", "-s", "Tests/Packaging"], timeout=120)
            pkg_ok = pkg_proc.returncode == 0
            outputs.append("[packaging tests]\n" + tail_output(pkg_proc, max_lines=80))

        if scope == "all" and swift_ok and pkg_ok:
            self.tests_passed_since_edit = True
        elif not swift_ok or not pkg_ok:
            self.tests_passed_since_edit = False

        return "\n\n".join(outputs)

    def _tool_finish(self, args: dict[str, Any]) -> str:
        still_unmerged = unmerged_files()
        if still_unmerged:
            raise RuntimeError(f"Unmerged files remain: {still_unmerged}")
        markers = files_with_conflict_markers([])
        if markers:
            raise RuntimeError(f"Conflict markers remain in: {markers}")
        if not self.tests_passed_since_edit:
            raise RuntimeError("Run run_tests(scope='all') and pass after your final edit before calling finish.")
        self.finished_summary = str(args.get("summary", "")).strip() or "Resolved conflicts and passed tests."
        return "Verification complete."


def call_chat_completions(
    endpoint: str,
    api_key: str,
    model: str,
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]],
) -> dict[str, Any]:
    """Call an OpenAI-compatible Chat Completions endpoint with bounded transient retries."""
    payload = json.dumps(
        {
            "model": model,
            "messages": messages,
            "tools": tools,
            "tool_choice": "auto",
            "temperature": 0.1,
        }
    ).encode("utf-8")

    last_error: Exception | None = None
    for attempt in range(3):
        req = urllib.request.Request(
            endpoint,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.code in {429, 500, 502, 503, 504} and attempt < 2:
                time.sleep(3 * (attempt + 1))
                last_error = RuntimeError(f"HTTP {exc.code}: {body[:500]}")
                continue
            raise RuntimeError(f"LLM API HTTP {exc.code}: {body[:1000]}") from exc
        except urllib.error.URLError as exc:
            if attempt < 2:
                time.sleep(3 * (attempt + 1))
                last_error = exc
                continue
            raise RuntimeError(f"LLM API request failed: {exc}") from exc

    raise RuntimeError(f"LLM API failed after retries: {last_error}")


def build_initial_prompt() -> str:
    """Gather git merge context and optional failing test log for the initial user prompt."""
    unmerged = unmerged_files()
    upstream_commits = run_cmd(["git", "log", "--oneline", "-n", "15", "HEAD..upstream/main"]).stdout.strip()
    fork_commits = run_cmd(["git", "log", "--oneline", "-n", "15", "upstream/main..HEAD"]).stdout.strip()
    status_short = run_cmd(["git", "status", "--short"]).stdout.strip()

    pre_test_excerpt = ""
    pre_test_log = os.environ.get("PRE_TEST_LOG", "").strip()
    if pre_test_log and pathlib.Path(pre_test_log).is_file():
        lines = pathlib.Path(pre_test_log).read_text(encoding="utf-8", errors="replace").splitlines()
        pre_test_excerpt = "\n".join(lines[-120:])

    sections = [
        "We just ran `git merge --no-commit --no-ff upstream/main` in `edhnt455/WonderBox` (fork of `jasonwong1991/WonderBox`).",
        "",
        "## Fork Rules You Must Preserve",
        "- Keep our fork's custom features (e.g. menu bar CPU/RAM coloring, stacked layout, hiding app icon) AND integrate upstream's fixes/features.",
        "- Keep `UpdateModels.swift` and `UpdateAndDiagnosticsTests.swift` pointing to `edhnt455/WonderBox` (do NOT revert them to `jasonwong1991/WonderBox`).",
        "- Follow upstream's app version number! When upstream bumps `CFBundleShortVersionString` / `CFBundleVersion` (e.g. 1.2.5 -> 1.2.6), make sure `Sources/WonderBox/Resources/Info.plist`, `Sources/WonderUninstallWatcher/Resources/Info.plist`, `Sources/WonderBox/Services/UpdateController.swift`, and `Tests/Packaging/test_release_one.py` all match the new upstream version consistently.",
        "- Never delete or weaken tests just to make them pass.",
        "- Do NOT run `git commit` or `git push`. After fixing, run `run_tests(scope='all')` and then call `finish`.",
        "",
        f"## Unmerged Files\n{json.dumps(unmerged, ensure_ascii=False)}",
        f"## Git Status\n{status_short or '(clean)'}",
        f"## Incoming Upstream Commits\n{upstream_commits or '(none)'}",
        f"## Fork Commits Ahead of Previous Upstream\n{fork_commits or '(none)'}",
    ]
    if pre_test_excerpt:
        sections.append(f"## Initial Test Failure Tail\n{pre_test_excerpt}")
    return "\n\n".join(sections)


def write_summary(summary_path: str, modified_files: list[str], summary_text: str) -> None:
    """Persist AI resolution metadata for downstream CI steps."""
    if not summary_path:
        return
    path = pathlib.Path(summary_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "modified_files": modified_files,
                "summary": summary_text,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


def main() -> int:
    endpoint = chat_completions_url(os.environ["LLM_BASE_URL"])
    api_key = os.environ["LLM_API_KEY"].strip()
    model = os.environ["LLM_MODEL"].strip()
    max_turns = max(1, int(os.environ.get("MAX_TURNS", "10")))
    summary_path = os.environ.get("SUMMARY_OUTPUT_FILE", "").strip()

    if not api_key or not model:
        print("Error: LLM_API_KEY and LLM_MODEL must be non-empty.", file=sys.stderr)
        return 1

    workspace = MergeResolverWorkspace()
    tools = workspace.tool_schemas()
    messages: list[dict[str, Any]] = [
        {
            "role": "system",
            "content": (
                "You are a senior Swift/macOS engineer resolving a git merge from upstream into a fork. "
                "Use the provided tools carefully, make minimal accurate edits, verify everything passes "
                "`run_tests(scope='all')`, and call `finish` once done."
            ),
        },
        {"role": "user", "content": build_initial_prompt()},
    ]

    for turn in range(1, max_turns + 1):
        print(f"[ai_resolve_merge] Turn {turn}/{max_turns}", flush=True)
        response = call_chat_completions(endpoint, api_key, model, messages, tools)
        choices = response.get("choices") or []
        if not choices:
            raise RuntimeError(f"Empty choices in LLM response: {response}")
        assistant_msg = choices[0]["message"]
        messages.append(assistant_msg)

        tool_calls = assistant_msg.get("tool_calls") or []
        if not tool_calls:
            if workspace.finished_summary is not None:
                break
            messages.append(
                {
                    "role": "user",
                    "content": "Continue using tools to resolve remaining issues, pass `run_tests(scope='all')`, and call `finish`.",
                }
            )
            continue

        for call in tool_calls:
            fn = call["function"]
            fn_name = fn["name"]
            raw_args = fn.get("arguments") or "{}"
            try:
                parsed_args = json.loads(raw_args)
            except json.JSONDecodeError as exc:
                result = f"Error: invalid JSON arguments for {fn_name}: {exc}"
            else:
                result = workspace.execute(fn_name, parsed_args)
            print(f"[ai_resolve_merge] tool={fn_name} -> {result[:180].splitlines()[0] if result else ''}", flush=True)
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": result,
                }
            )

        if workspace.finished_summary is not None:
            write_summary(summary_path, sorted(workspace.modified_files), workspace.finished_summary)
            print("[ai_resolve_merge] Completed successfully.", flush=True)
            return 0

    print(
        f"[ai_resolve_merge] Failed to finish within {max_turns} turns. "
        f"Unmerged={unmerged_files()}, markers={files_with_conflict_markers([])}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
