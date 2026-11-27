#!/usr/bin/env python3
"""Send WonderBox upstream sync status notifications to Bark."""

from __future__ import annotations

import json
import os
import sys
import urllib.request


def build_payload() -> dict[str, str]:
    """Construct the Bark JSON notification payload from CI environment variables."""
    status = os.environ.get("SYNC_STATUS", "failure")
    ai_used = os.environ.get("AI_USED", "false") == "true"
    published = os.environ.get("PUBLISHED_RELEASE", "false") == "true"
    app_version = os.environ.get("APP_VERSION", "").strip()
    release_tag = os.environ.get("RELEASE_TAG", "").strip() or (f"v{app_version}" if app_version else "")
    upstream_sha = os.environ.get("UPSTREAM_SHA", "").strip()
    commit_sha = os.environ.get("COMMIT_SHA", "").strip()
    failed_stage = os.environ.get("FAILED_STAGE", "").strip() or "未知阶段"
    run_url = os.environ.get("RUN_URL", "").strip()
    repo_url = os.environ.get("REPO_URL", "").strip().rstrip("/")
    ai_summary_file = os.environ.get("AI_SUMMARY_FILE", "").strip()

    ai_files_text = ""
    if ai_summary_file and os.path.isfile(ai_summary_file):
        try:
            with open(ai_summary_file, encoding="utf-8") as fh:
                data = json.load(fh)
            files = data.get("modified_files") or []
            if files:
                preview = ", ".join(files[:5])
                if len(files) > 5:
                    preview += f" 等 {len(files)} 个文件"
                ai_files_text = f"AI 处理文件：{preview}\n"
        except (OSError, json.JSONDecodeError):
            pass

    target_url = f"{repo_url}/releases/tag/{release_tag}" if published and release_tag else (
        f"{repo_url}/commit/{commit_sha}" if status == "success" and commit_sha else run_url
    )

    if status != "success":
        title = "WonderBox 上游自动同步失败"
        body = f"失败阶段：{failed_stage}（upstream {upstream_sha or 'unknown'}）\n已安全中止，main 分支未受影响，点击查看日志。"
        level = "time-sensitive"
    elif ai_used and published:
        title = f"WonderBox {release_tag} 已由 AI 合并并发布"
        body = f"{ai_files_text}已合并 upstream ({upstream_sha})，通过全部测试并上传 Release 安装包。"
        level = "time-sensitive"
    elif ai_used:
        title = "WonderBox 冲突已由 AI 自动合并"
        body = f"{ai_files_text}已合并 upstream ({upstream_sha}) 并通过测试与打包验证，点击查看提交。"
        level = "time-sensitive"
    elif published:
        title = f"WonderBox {release_tag} 已自动同步并发布"
        body = f"已无冲突合并 upstream ({upstream_sha})，测试通过并上传 WonderBox-{app_version}.zip 至 Release。"
        level = "active"
    else:
        title = "WonderBox 已同步上游提交"
        body = f"已无冲突合并 upstream ({upstream_sha}) 并通过测试与打包验证，点击查看提交。"
        level = "active"

    if len(body) > 380:
        body = body[:377] + "..."

    payload = {
        "title": title,
        "body": body,
        "group": "WonderBox-Sync",
        "level": level,
    }
    if target_url:
        payload["url"] = target_url
    return payload


def main() -> int:
    dry_run = "--dry-run" in sys.argv or os.environ.get("DRY_RUN") == "1"
    bark_url = os.environ.get("BARK_URL", "").strip().rstrip("/")
    payload = build_payload()

    if dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    if not bark_url:
        print("Warning: BARK_URL secret is not set; skipping Bark notification.", file=sys.stderr)
        return 0

    req = urllib.request.Request(
        bark_url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        print(f"Bark notification sent: HTTP {resp.status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
