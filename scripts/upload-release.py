#!/usr/bin/env python3
"""把 build/dmg/ 里的 DMG、ZIP、latest.json 分块上传到 ChillSkill API(GitHub Actions OIDC 鉴权)。

用法:OIDC_TOKEN=<jwt> scripts/upload-release.py [--dir build/dmg] [--api https://api.chillskill.xyz]
顺序:先传 DMG/ZIP,最后传 latest.json(服务端收到 latest.json 才切换「最新」并清理旧版本)。
只用标准库,方便在 CI runner 上直接跑。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


class TrustDowngrade(Exception):
    """服务端拒绝用信任等级更低的包覆盖已公证版本(CI 未配签名/公证 secrets 时的正常结果)。"""


def call(api: str, method: str, path: str, token: str, body: bytes | None = None, ctype: str = "application/json") -> dict:
    req = urllib.request.Request(f"{api}{path}", data=body, method=method,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode(errors="replace")
        if e.code == 409 and "trust_downgrade" in text:
            raise TrustDowngrade(text[:300])
        raise SystemExit(f"{method} {path} → HTTP {e.code}: {text[:300]}")


def upload_file(api: str, token: str, path: Path) -> dict:
    data = path.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    begin = call(api, "POST", "/v1/releases/upload/begin", token,
                 json.dumps({"file": path.name, "size": len(data), "sha256": sha}).encode())
    uid, chunk = begin["upload_id"], int(begin["chunk_size"])
    parts = [data[i:i + chunk] for i in range(0, len(data), chunk)] or [b""]
    for i, part in enumerate(parts):
        call(api, "PUT", f"/v1/releases/upload/{uid}/{i}", token, part, "application/octet-stream")
    done = call(api, "POST", f"/v1/releases/upload/{uid}/finish", token, json.dumps({"chunks": len(parts)}).encode())
    print(f"uploaded {path.name} ({len(data)} bytes, {len(parts)} chunks) → published={done.get('published')}")
    return done


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/dmg")
    ap.add_argument("--api", default=os.environ.get("CHILLSKILL_API", "https://api.chillskill.xyz"))
    args = ap.parse_args()
    token = os.environ.get("OIDC_TOKEN", "")
    if not token:
        raise SystemExit("OIDC_TOKEN 未设置")
    d = Path(args.dir)
    meta = json.loads((d / "latest.json").read_text())
    for name in (meta["file"], meta.get("zip_file")):
        if name:
            upload_file(args.api, token, d / name)
    result = {"published": False, "build": meta.get("build"), "file": meta.get("file")}
    try:
        upload_file(args.api, token, d / "latest.json")
        result["published"] = True
    except TrustDowngrade as e:
        result["reason"] = "trust_downgrade"
        result["detail"] = str(e)
        print(f"NOT PUBLISHED (trust_downgrade): {e}")
    (d / "upload-result.json").write_text(json.dumps(result))
    print("done", json.dumps(result))


if __name__ == "__main__":
    main()
