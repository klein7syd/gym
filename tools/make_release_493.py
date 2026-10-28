#!/usr/bin/env python3
"""创建 v4.9.3 Release 并上传未签名 IPA 附件（免登录直链）。"""

import json
import os
import subprocess
import urllib.error
import urllib.request

OWNER = "klein7syd"
REPO = "gym"
TAG = "v4.9.3"
IPA = "REPS-4.9.3-unsigned.ipa"


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

BODY = """## 4.9.3 — 修播放页下拉时的持续抖动 / 闪烁

### 1. 根因：DragGesture 用了 .local 坐标空间
手势挂在抓手 / 头部 / 封面 / 标题区上，这几个视图都在**被 `.offset(y: dragOffset)` 移动的卡片内部**。
`.local` 是视图自身坐标：手指往下一动 → 视图跟着下移 → 手指在局部坐标里的 y 被抵消 →
`translation.height` 变小 → `dragOffset` 变小 → 卡片弹回去 → 下一帧 translation 又变大……
正反馈回路，表现为持续抖动；`pull` 同时来回跳，底下 TabView 的缩放 / 压暗 / 圆角一起抖。

改成 `DragGesture(minimumDistance: 8, coordinateSpace: .global)`：全局坐标不随卡片位移变化。
threshold（110 / 260）、260pt 满进度、0.34 spring 全部不变。

### 2. 拖动期间不再切整窗口配色
4.9.2 在拖动第一帧就 `forceDark = false`，整窗口 userInterfaceStyle 中途变化会触发全窗口重绘，
叠在拖动每帧刷新上就是第二处闪烁。现在：
- 删掉 `beginDismiss()` / `cancelDismiss()` 及 `dismissing` 标记；
- 拖动全程 `forceDark` 保持 true（播放页与压暗层本身就是深色，视觉连续）；
- 弹回：什么都不做，配色不变；
- 关闭：**先**起关闭动画，`asyncAfter(0.30)` 再在回调里（复查 `!isOpen`）无动画切回浅色。
- `open()` 不变：0.52s 后置 true，回调复查 `isOpen`；⌄ 按钮走同一个 `close()`。

### 3. 封面去掉隐式动画
`cover(side:)` 上的 `.animation(.easeOut(duration: 0.25), value: side)` 已删除，不再替代。
side 在拖动 / 安全区回退时会变，那个 0.25s 动画让封面相对卡片滞后，出现错位撕裂帧。

### 4. 压暗遮罩抽成 DimOverlay
`Color.black.opacity(0.42 * (1 - pull))` 抽成只观察 player 的小视图，数值与 spring（0.46/0.90）不变。
scaleEffect 与 CardClip 半径仍留在 RootTabView。

### 已知
- 未在真机验证：CI 只验证编译、包结构、版本号。
- RootTabView 的 body 仍然读 `pull`（scaleEffect / CardClip 半径），所以拖动时根视图**依旧**每帧求值；
  DimOverlay 的抽取只是让遮罩层不再由根视图构造，真正止抖的是第 1 条。
  彻底方案是整层卡片堆叠抽成子视图，本版未做。
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
        "name": "REPS 4.9.3 — 修播放页下拉抖动",
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
