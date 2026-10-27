#!/usr/bin/env python3
"""把当前工作区的提交内容推到 GitHub（走 REST API，不用 git 传输）。

为什么需要这个：
这台机器到 github.com:443 的 git 协议被代理挡住（CONNECT 502 / Empty reply），
但 api.github.com 是通的。所以用 Git Data API 把文件树复刻上去。

用法：
    python tools/push-via-api.py                 # 用 HEAD 的提交信息
    python tools/push-via-api.py "自定义提交信息"

凭据：优先读环境变量 GITHUB_TOKEN，否则用本机已保存的 git 凭据（git credential fill）。

注意：GitHub 内部序列化 tree 的方式和本地 git 有差异，远端算出的 tree sha 和本地不同，
所以远端/本地的 commit sha 不会一致（内容一致）。有网的时候执行
`git fetch origin && git reset --hard origin/main` 即可对齐本地历史。
"""

import base64
import datetime
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

OWNER = os.environ.get("REPS_REPO_OWNER", "klein7syd")
REPO = os.environ.get("REPS_REPO_NAME", "gym")
BRANCH = os.environ.get("REPS_BRANCH", "main")
API = "https://api.github.com"


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
    raise SystemExit("找不到 GitHub 凭据，请设置 GITHUB_TOKEN 环境变量")


TOKEN = token()


def api(method, path, payload=None, allow=()):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        API + path, data=data, method=method,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Accept": "application/vnd.github+json",
            "User-Agent": "reps-push",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as f:
            body = f.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:1200]
        if e.code in allow:
            return {}
        raise SystemExit(f"API {method} {path} -> {e.code}\n{detail}")


def git(*args):
    out = subprocess.run(["git", *args], capture_output=True, check=True)
    return out.stdout.decode("utf-8", "replace").strip()


def remote_head():
    r = api("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/{BRANCH}", allow=(404, 409))
    return r.get("object", {}).get("sha") if r else None


def remote_file_shas(tree_sha):
    if not tree_sha:
        return {}
    t = api("GET", f"/repos/{OWNER}/{REPO}/git/trees/{tree_sha}?recursive=1")
    return {e["path"]: e["sha"] for e in t.get("tree", []) if e["type"] == "blob"}


def main():
    message = sys.argv[1] if len(sys.argv) > 1 else git("log", "-1", "--pretty=%B")

    head = remote_head()
    if head:
        base = api("GET", f"/repos/{OWNER}/{REPO}/git/commits/{head}")
        existing = remote_file_shas(base["tree"]["sha"])
        print(f"远端 HEAD {head[:8]}，已有 {len(existing)} 个文件")
    else:
        existing = {}
        print("远端为空仓库")

    rows = [l for l in git("ls-files", "-s").splitlines() if l.strip()]
    print(f"本地索引 {len(rows)} 个文件")

    entries, uploaded = [], 0
    for line in rows:
        meta, path = line.split("\t", 1)
        mode, sha, _stage = meta.split()
        if existing.get(path) == sha:
            entries.append({"path": path, "mode": mode, "type": "blob", "sha": sha})
            continue
        content = subprocess.run(["git", "cat-file", "blob", sha], capture_output=True, check=True).stdout
        r = api("POST", f"/repos/{OWNER}/{REPO}/git/blobs",
                {"content": base64.b64encode(content).decode(), "encoding": "base64"})
        entries.append({"path": path, "mode": mode, "type": "blob", "sha": r["sha"]})
        uploaded += 1
    print(f"新上传 {uploaded} 个文件")

    tree = api("POST", f"/repos/{OWNER}/{REPO}/git/trees", {"tree": entries})
    print(f"tree {tree['sha'][:8]}")

    now = datetime.datetime.now().astimezone()
    stamp = now.strftime("%Y-%m-%dT%H:%M:%S%z")
    identity = {
        "name": git("config", "user.name") or "REPS",
        "email": git("config", "user.email") or "reps@localhost",
        "date": stamp[:-2] + ":" + stamp[-2:],
    }

    commit = api("POST", f"/repos/{OWNER}/{REPO}/git/commits", {
        "message": message,
        "tree": tree["sha"],
        "parents": [head] if head else [],
        "author": identity,
        "committer": identity,
    })
    print(f"commit {commit['sha'][:8]}")

    if head:
        api("PATCH", f"/repos/{OWNER}/{REPO}/git/refs/heads/{BRANCH}",
            {"sha": commit["sha"], "force": True})
    else:
        api("POST", f"/repos/{OWNER}/{REPO}/git/refs",
            {"ref": f"refs/heads/{BRANCH}", "sha": commit["sha"]})

    subprocess.run(["git", "update-ref", f"refs/remotes/origin/{BRANCH}", commit["sha"]], check=False)
    print(f"已推送 -> https://github.com/{OWNER}/{REPO}/commit/{commit['sha']}")


if __name__ == "__main__":
    main()
