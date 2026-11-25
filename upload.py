#!/usr/bin/env python3
"""用 Contents API 上传/更新文件（绕开 git push 的代理故障）。"""
import base64
import json
import os
import sys
import urllib.request

OWNER = "i76112102-web"
REPO = "ax-hud-overlay-poc"
BRANCH = "main"
TOKEN = os.environ["GITHUB_TOKEN"]
API = f"https://api.github.com/repos/{OWNER}/{REPO}/contents"


def req(url, method="GET", payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {TOKEN}")
    r.add_header("Accept", "application/vnd.github+json")
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return {"_status": e.code, "_body": e.read().decode()[:300]}


def main(paths, message):
    for p in paths:
        cur = req(f"{API}/{p}?ref={BRANCH}")
        sha = cur.get("sha") if "sha" in cur else None
        with open(p, "rb") as f:
            content = base64.b64encode(f.read()).decode()
        payload = {"message": message, "content": content, "branch": BRANCH}
        if sha:
            payload["sha"] = sha
        res = req(f"{API}/{p}", "PUT", payload)
        if "_status" in res:
            print(f"FAIL {p}: {res['_status']} {res['_body']}")
            return 1
        print(f"OK   {p} -> {res['commit']['sha'][:10]}")
    return 0


if __name__ == "__main__":
    msg = sys.argv[1]
    sys.exit(main(sys.argv[2:], msg))
