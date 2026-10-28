#!/usr/bin/env python3
"""创建 v4.9.1 Release 并上传未签名 IPA 附件（免登录直链）。"""

import json
import os
import subprocess
import urllib.error
import urllib.request

OWNER = "klein7syd"
REPO = "gym"
TAG = "v4.9.2"
IPA = "REPS-4.9.2-unsigned.ipa"


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

BODY = """## 4.9.2 — 修播放页下拉/关闭时的深浅色闪烁 · 各处行距

### 1. 闪烁的根因：窗口配色切晚了一步
下拉时 `forceDark` 还是 true，窗口是深色，底下露出来的整页是深色版；
松手才切回浅色 —— 露在外面的那一页当场由深变浅，这就是那道闪。
另外移出过渡带 opacity 淡出，半透明的几帧会透出底下那层，再闪一次。

改法（原则：配色切换只能发生在播放页仍盖满屏的时候）：
- `beginDismiss()`：拖动**第一帧**（位移 8pt、底下几乎没露出）就把窗口切回浅色，
  用 `disablesAnimations` 的 Transaction 关掉动画。
- `cancelDismiss()`：没拖够弹回时，0.36s（弹回 spring 是 0.34s）后再置回 true，
  回调里复查 `isOpen && pull == 0`。
- `close()`：先切浅色，`asyncAfter(0.05)` 再启动下滑动画 —— 让配色先渲染一帧；
  拖动路径已经切过就立刻下滑，不再等。
- `open()`：0.52s 的延迟回调里加 `isOpen` 复查，防止 0.52s 内又关掉后把窗口切成深色。
- 移出过渡改成 `.move(edge: .bottom)`，不再淡出。

### 2. 行距
- 专辑详情：曲目行 9→13、最少 52pt 高、曲名行距 3；头部 12/3→16/6、专辑名行距 3、
  艺人行距 2、上边距 12→16；按钮区 20/14→22/18；曲目表上下 4→6。
- 搜索结果行 / 本地行：上下 8→11，两行文字间距 2→4；专辑格子 6→8 + 副标题 +2。
- 播放页：标题区 2→5 且两行各加行距 2；训练卡文字间距 4→6、上下 12→14、小按钮 8→9；
  固定高度 448→462（+3 标题 +4 文字间距 +4 内边距 +2 按钮 +1 余量）。
- 训练面板：外层 14→16、动作卡 6→8 且内边距 16→18、休息卡 3→5 内边距 14→16、
  记录卡 10→12 行距 2→6 内边距 16→18。
- 训练页：动作卡 6→9、休息卡 10→12、组列表行 9→13，多行文字加行距。

### 已知
- 未在真机验证：CI 只验证编译、包结构、版本号。
- `pull` 每帧都是 `@Published`，拖动时整个 RootTabView 会重算（含 mask 重光栅化）。
  本版未动，最小优化方案见交付说明。
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
        "name": "REPS 4.9.2 — 修播放页下拉闪烁 · 行距",
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
