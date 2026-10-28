#!/usr/bin/env python3
"""创建 v4.9.0 Release 并上传未签名 IPA 附件（免登录直链）。

凭据优先读环境变量 GITHUB_TOKEN / REPS_TOKEN，否则用 git credential fill。
"""

import json
import os
import subprocess
import urllib.error
import urllib.request

OWNER = "klein7syd"
REPO = "gym"
TAG = "v4.9.0"
IPA = "REPS-4.9.0-unsigned.ipa"


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

BODY = """## 4.9.0 — 上下大黑边（真正的原因）

### 病因
`TabView` 和播放页都是**按安全区布局**的。它们里面的背景虽然 `ignoresSafeArea()` 能画到
状态栏和底部横条上，但只要这条链路上套了 `.clipShape(RoundedRectangle(cornerRadius: …))`，
**裁剪边就是安全区矩形 —— 哪怕圆角是 0 也会硬切一刀**，把铺出去的那部分削平，
露出来就是底下的深色层。表现就是一进 App（进任何一页）上下各一条大黑边，
进播放页同样。

4.6 加卡片堆叠效果时给 TabView 套了 `.clipShape`，黑边就是从那一版开始的；
4.8 只调了播放页的修饰符顺序、裁剪还在，所以「依旧」。

### 改法
新增 `CardClip` 修饰符（`Theme.swift`）：**圆角为 0 时什么都不做**，只有真正要圆角才裁。

| 位置 | 以前 | 现在 |
|---|---|---|
| 根 TabView | 无条件 `.clipShape(RoundedRectangle(cornerRadius: isOpen ? 34-20*pull : 0))` | `.modifier(CardClip(active: isOpen, radius: …))`，收起时不裁 |
| 播放页 NowPlayingView | 无条件 `.clipShape(RoundedRectangle(cornerRadius: min(34, drag/5)))` | `.modifier(CardClip(active: drag > 0.5, radius: …))`，静止不裁 |

### 顺带
- 根视图底层原来是纯黑 `Color.black.ignoresSafeArea()`，现在常态铺**页面同色**
  （`AppBackground`），只有播放页打开时才换成播放页自己的深灰 `#212121` —— 以后任何一处
  没铺到的安全区，露出来的也是同一个颜色，不可能再出现黑条。
- 版本 4.9.0（build 10）。

### 已知限制
- 整首播放要求歌已在 Apple Music「资料库」（自签没有 MusicKit entitlement）。
- 系统音量仍是 16 级（`MPVolumeView` 内部 UISlider 的固有限制）。
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
        "name": "REPS 4.9.0 — 修上下大黑边（clipShape 按安全区硬切）",
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
