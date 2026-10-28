#!/usr/bin/env python3
"""创建 v4.9.6 Release 并上传未签名 IPA 附件（免登录直链）。"""

import json
import os
import subprocess
import urllib.error
import urllib.request

OWNER = "klein7syd"
REPO = "gym"
TAG = "v4.9.6"
IPA = "REPS-4.9.6-unsigned.ipa"


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

BODY = """## 4.9.6 — 两阶段训练状态机 · 下拉黑边 · 松手跳变 · 键盘叠加 · 缩放

### A. 训练 / 组间歇 两阶段状态机
working --「完成这一组」--> 记录一组 + resting --归零 /「跳过休息」--> working → 下一组
- 状态：`RestTimer.isResting`（= isRunning）；新增 `workStart` + `beginWork()`，skip/finish 末尾都调用；
- 圈：`RestRing` / `MiniRestRing` 新增 `color` 参数，working 蓝（WorkStyle.ring）、resting 绿（RestStyle.ring）；
- 训练页：常驻 phaseCard，working 显示蓝圈本组用时（TimelineView 每秒，不新开 Timer）、
  resting 显示绿圈倒计时 + 「+30 秒 / 跳过休息」；底部主按钮按阶段切换；删掉 60/90/120/180 预设芯片；
- 播放页训练卡 / 训练面板同规则：「完成」只在 working，「+30 / 跳过」只在 resting，
  删掉手动开始休息的「120s」按钮；三处 completeSet 都加了 `guard !rest.isResting`。

### B. 下拉时的灰带 + 黑圈
根因：底层除了 AppBackground 还叠了 `Color(white: 0.13)`，那层没有 ignoresSafeArea ——
缩小后四周露深灰、上下安全区露浅灰。整层删除，底层只剩铺满安全区的 AppBackground。

### C. 滑到底松手「跳一下」
`close()` 原本先 `pull = 0` 再起关闭动画，pull 一旦归零，下层立刻从「几乎原样」缩回最小尺寸。
改成不立刻清零，等 0.6s 关闭动画结束后再复位（此时 isOpen=false，复位不可见）。

### D. 键盘叠在播放器上
`open()` 与 `NowPlayingView.onAppear` 都收键盘；播放页与两处 MiniPlayerBar 加
`.ignoresSafeArea(.keyboard, edges: .bottom)`；底层 TabView 加 `.accessibilityHidden`。

### E. 下拉缩放过大
缩放 0.94+0.06 → 0.97+0.03、圆角 34-20 → 22-12、压暗 0.42 → 0.28（幅度 6% → 3%）。

### 已知
- 未在真机验证：CI 只验证编译、包结构、版本号、符号。
- 训练页「本组用时」按 workStart 起算，App 重启后从启动时刻算（不落盘，符合任务书）。
- RestRing 额外加了一个 `caption` 参数（默认「休息中」），working 时显示「本组用时」，
  否则训练阶段的圈里会写着「休息中」。
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
        "name": "REPS 4.9.6 — 两阶段训练/休息 · 黑边 · 跳变 · 键盘",
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
