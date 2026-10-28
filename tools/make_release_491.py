#!/usr/bin/env python3
"""创建 v4.9.1 Release 并上传未签名 IPA 附件（免登录直链）。"""

import json
import os
import subprocess
import urllib.error
import urllib.request

OWNER = "klein7syd"
REPO = "gym"
TAG = "v4.9.1"
IPA = "REPS-4.9.1-unsigned.ipa"


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

BODY = """## 4.9.1 — CardClip 不再重建视图 · 安全区兜底 · 本地高亮按 id

### 1. CardClip 用 mask 代替 clipShape（结构恒定）
4.9.0 的 `CardClip` 用 `if active { 裁 } else { 原样 }`，两个分支是不同的结构身份
(`_ConditionalContent`)。`active` 一翻转，SwiftUI 就把 `content` 销毁重建 ——
对根 TabView 来说就是打开/关闭播放页时会丢：选中的 tab、各页滚动位置、NavigationStack 路径，
过渡也退化成淡入淡出。

现在 `body` 永远返回同一种结构：

```swift
content.mask {
    RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
        .ignoresSafeArea()
}
```

`effectiveRadius = (active && radius > 0.01) ? radius : 0`。结构不变，只有数值在变，
状态不丢，圆角也能被外层 `.animation(…, value: player.isOpen)` 连续驱动。

mask 里的形状带 `.ignoresSafeArea()`：圆角为 0 时它是一块**覆盖整屏（含状态栏 / 底部横条）
的矩形**，不像 `clipShape` 那样沿安全区矩形切边，所以黑边修复依然成立。

### 2. 播放页修饰符顺序：背景 → CardClip → offset
遮罩要盖在卡片本身上，再让整张卡片位移，圆角才会跟着走；反过来遮罩会留在原地。

### 3. SafeArea.insets 兜底改成灵动岛基准
- 场景选择：优先 `activationState == .foregroundActive`，回退第一个；
- 窗口：优先 keyWindow，回退 `windows.first`；
- 取不到（或首帧 `top == 0` 还没布局）时回退 **top 59 / bottom 34**，原来回退 47 且可能返回 0。

### 4. 本地曲目高亮按 id 比较
`PlayItem.id` 对本地曲目就是 `Track.id.uuidString`，所以同名歌不会再一起高亮。

### 5. 底层色淡入
`Color(white: 0.13)` 的 opacity 加了 `.animation(.easeInOut(duration: 0.25), value: player.isOpen)`，
和 TabView 的 spring 大致同步，减少硬切。

### 已知
- 未在真机验证，mask + ignoresSafeArea 的实际渲染需要上机确认。
- 关闭播放页时 `forceDark = false` 早于关闭动画，状态栏文字会在 0.4s 内变暗（详见交付说明）。
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
        "name": "REPS 4.9.1 — CardClip 改 mask（不重建视图）· 安全区兜底 · 本地高亮按 id",
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
