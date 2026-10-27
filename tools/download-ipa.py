#!/usr/bin/env python3
"""下载最新一次成功构建的 IPA 产物到本地 dist/ 目录。

用法：python tools/download-ipa.py
产物：dist/REPS-unsigned.ipa
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile

OWNER = "klein7syd"
REPO = "gym"
API = "https://api.github.com"
OUT_DIR = "dist"


def token():
    tok = os.environ.get("GITHUB_TOKEN")
    if tok:
        return tok.strip()
    out = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n\n",
        capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line[len("password="):].strip()
    raise SystemExit("找不到 GitHub 凭据")


TOKEN = token()


def api(path):
    req = urllib.request.Request(
        API + path,
        headers={"Authorization": "Bearer " + TOKEN,
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "reps"},
    )
    with urllib.request.urlopen(req, timeout=120) as f:
        return json.loads(f.read())


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def download(url, auth=True):
    req = urllib.request.Request(url)
    if auth:
        req.add_header("Authorization", "Bearer " + TOKEN)
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req, timeout=180) as f:
            return f.read()
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            return download(e.headers["Location"], auth=False)
        raise


def main():
    runs = api(f"/repos/{OWNER}/{REPO}/actions/runs?per_page=10")["workflow_runs"]
    good = [r for r in runs if r["conclusion"] == "success"]
    if not good:
        latest = runs[0] if runs else None
        if latest:
            print(f"还没有成功的构建。最近一次：{latest['status']}/{latest['conclusion']} {latest['head_sha'][:8]}")
        else:
            print("还没有任何构建记录")
        return 1

    run = good[0]
    print(f"使用构建：{run['head_sha'][:8]}  {run['created_at']}")

    arts = api(f"/repos/{OWNER}/{REPO}/actions/artifacts?per_page=50")["artifacts"]
    arts = [a for a in arts if a["workflow_run"]["id"] == run["id"] and not a.get("expired")]
    if not arts:
        print("这次构建没有产物")
        return 1
    art = arts[0]
    print(f"产物：{art['name']}  {art['size_in_bytes']/1048576:.1f} MB")

    data = download(art["archive_download_url"])
    os.makedirs(OUT_DIR, exist_ok=True)
    zpath = os.path.join(OUT_DIR, "artifact.zip")
    with open(zpath, "wb") as f:
        f.write(data)
    with zipfile.ZipFile(zpath) as z:
        names = z.namelist()
        print("压缩包内：", names)
        ipa = [n for n in names if n.endswith(".ipa")][0]
        target = os.path.join(OUT_DIR, "REPS-unsigned.ipa")
        with z.open(ipa) as src, open(target, "wb") as dst:
            dst.write(src.read())
    os.remove(zpath)
    print(f"已保存：{os.path.abspath(target)}  ({os.path.getsize(target)/1048576:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
