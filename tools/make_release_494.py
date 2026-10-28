#!/usr/bin/env python3
"""创建 v4.9.4 Release 并上传未签名 IPA 附件（免登录直链）。"""

import json
import os
import subprocess
import urllib.error
import urllib.request

OWNER = "klein7syd"
REPO = "gym"
TAG = "v4.9.4"
IPA = "REPS-4.9.4-unsigned.ipa"


def token():
    for key in ("REPS_TOKEN", "GITHUB_TOKEN"):
        v = os.environ.get(key)
        if v:
            return v.strip()
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

BODY = """## 4.9.4 — 修「下拉关闭播放页时，底下页面深色/亮色跳变」

### 根因
下拉期间底下露出哪一版 TabView，取决于 `PlayerPresenter.forceDark`。
4.9.3 为避免闪烁让拖动全程 `forceDark = true`，于是：
- 下拉时露出的是**深色版**页面；
- 关闭时（0.30s 回调）才切回浅色 → 那一整页当场由深变亮 = 跳变。
4.9.2 的思路才是对的：下拉露出来的应当一开始就是最终那版浅色，
所以切色必须发生在**拖动第一帧**（位移几 pt、底下几乎没露出）。
当时之所以会闪，根因是 `DragGesture` 的 `.local` 坐标空间（已用 `.global` 修掉），
和配色切换无关 —— 两件事要分开。

### 改法
- 恢复 `beginDismiss()`：`guard forceDark`，用 `disablesAnimations` 的 Transaction 无动画置 false。
- 新增 `isDragging`（普通属性，非 @Published，避免多余刷新）+ `setDragging(_:)`。
- 恢复 `cancelDismiss()`：0.36s 后复查 `isOpen && pull == 0 && !isDragging` 再置回 true。
- `close()` 恢复 4.9.2 逻辑：有深色就先无动画切浅色、`asyncAfter(0.05)` 再起下滑动画；
  已经切过就直接下滑。删掉「0.30s 后才切色」的整段回调（它就是跳变来源）。
- `dismissDrag.onChanged`：`h > 0 && !dismissing` 时 `dismissing = true` → `setDragging(true)` → `beginDismiss()`。
- `dismissDrag.onEnded`：`dismissing = false`、`setDragging(false)`；far → close()；
  否则弹回并 `cancelDismiss()`。
- `open()` 的 0.52s 回调额外加 `!isDragging` 守卫（见「本版偏离说明」）。
- 手势仍是 `.global`，封面仍无隐式动画（已核查，未回退）。

### 本版偏离说明（一处）
`open()` 的 0.52s 回调原本只查 `isOpen`。新增了 `!isDragging`：
若用户在打开后 0.3s 左右就开始下拉（播放页还在滑入、forceDark 仍为 false），
0.52s 回调会把窗口切成深色 —— 正好在拖动中途翻色，还是要修的那道跳变。
加上守卫后这种情况保持浅色，由 `cancelDismiss` 的 0.36s 回调兜底恢复深色。
除这一个条件外，`open()` 与任务书一致。

### 已知（预期行为）
下拉最初那几 pt（也就是切配色的那一帧），状态栏文字会瞬间由白变黑、短暂压在深色播放页上。
这是「把切色提前到几乎看不见位移的那一帧」的必然代价，属预期，不是 bug。

### 其它已知
- 未在真机验证：CI 只验证编译、包结构、版本号、符号。
- RootTabView body 仍读 `pull`，拖动时依旧每帧求值（scaleEffect / CardClip 半径必须在 TabView 上）。
- 整首播放要求歌已在 Apple Music「资料库」；系统音量仍 16 级。
"""


def api(method, url, payload=None, raw=None, ctype="application/json"):
    data = raw if raw is not None else (json.dumps(payload).encode() if payload is not None else None)
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
        "User-Agent": "reps-release",
        "Content-Type": ctype,
    })
    try:
        with urllib.request.urlopen(req, timeout=300) as f:
            body = f.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        print("ERR", e.code, e.read().decode("utf-8", "replace")[:600])
        raise


def main():
    base = f"https://api.github.com/repos/{OWNER}/{REPO}"
    rel = api("POST", base + "/releases", {
        "tag_name": TAG,
        "target_commitish": "main",
        "name": "REPS 4.9.4 — 修下拉时底下页面深浅跳变",
        "body": BODY,
    })
    print("release", rel["id"], rel["tag_name"])

    with open(IPA, "rb") as f:
        blob = f.read()
    print("上传", IPA, f"{len(blob)/1048576:.2f} MB")
    asset = api("POST",
                f"https://uploads.github.com/repos/{OWNER}/{REPO}/releases/{rel['id']}/assets?name={IPA}",
                raw=blob, ctype="application/octet-stream")
    print("asset", asset["name"], asset["size"], asset.get("digest"))
    print("直链", asset["browser_download_url"])


if __name__ == "__main__":
    main()
