#!/usr/bin/env python3
"""创建 Release 并上传 IPA。"""
import json
import os
import pathlib
import sys
import urllib.request

OWNER = "i76112102-web"
REPO = "ax-hud-overlay-poc"
TOKEN = os.environ["GITHUB_TOKEN"]
API = f"https://api.github.com/repos/{OWNER}/{REPO}"


def call(url, method="GET", payload=None, ctype="application/json"):
    data = payload if isinstance(payload, bytes) else (
        json.dumps(payload).encode() if payload is not None else None)
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {TOKEN}")
    r.add_header("Accept", "application/vnd.github+json")
    if data:
        r.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return {"_status": e.code, "_body": e.read().decode()[:400]}


def main():
    dist = pathlib.Path(sys.argv[1])
    tag = "v1.0.0"
    notes = (dist / "build-info.txt").read_text(encoding="utf-8")
    notes += "\n\n```\n" + (dist / "SHA256SUMS.txt").read_text(encoding="utf-8") + "```\n"

    rel = call(f"{API}/releases", "POST", {
        "tag_name": tag,
        "name": f"{tag} — unsigned IPA",
        "body": notes,
        "draft": False,
        "prerelease": False,
    })
    if "_status" in rel:
        if rel["_status"] == 422:
            rel = call(f"{API}/releases/tags/{tag}")
        if "_status" in rel:
            print("release failed:", rel)
            return 1
    rid = rel["id"]
    print(f"release {rid} tag={rel['tag_name']}")

    for name in ("PiPOverlay.ipa", "HUDKeepAlive.ipa", "ScreenShield.ipa",
                 "SHA256SUMS.txt", "build-info.txt"):
        p = dist / name
        if not p.exists():
            print("skip missing", name)
            continue
        res = call(f"https://uploads.github.com/repos/{OWNER}/{REPO}/releases/{rid}/assets?name={name}",
                   "POST", p.read_bytes(), "application/octet-stream")
        if "_status" in res:
            print(f"FAIL {name}: {res['_status']} {res['_body']}")
            return 1
        print(f"OK   {name} ({res.get('size')} bytes)")
    print("https://github.com/%s/%s/releases/tag/%s" % (OWNER, REPO, tag))
    return 0


if __name__ == "__main__":
    sys.exit(main())
