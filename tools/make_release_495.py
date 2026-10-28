#!/usr/bin/env python3
"""创建 v4.9.5 Release 并上传未签名 IPA 附件（免登录直链）。"""

import json
import os
import subprocess
import urllib.error
import urllib.request

OWNER = "klein7syd"
REPO = "gym"
TAG = "v4.9.5"
IPA = "REPS-4.9.5-unsigned.ipa"


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

BODY = """## 4.9.5 — 组间休息：绿色倒计时环 + 时长可调

### 1. 颜色：休息 = 绿，训练 = 蓝
新增 `RestStyle.ring = Color.green`（Theme.swift）。
`RestRing`（训练页）与 `MiniRestRing`（播放页训练卡 / TrainingSheet）的**进度弧**改用 `RestStyle.ring`；
底环颜色、尺寸、线宽、0.2s linear 动画全部保持原样。
两个环中间的倒计时文字本来就是 `.primary`（不是 accentColor），按规则不动。
训练页的预设芯片、按钮、选中态等 accentColor 一律未动。

### 2. 训练页新增休息时长 Stepper 入口
`exerciseCard` 下方常驻一行「组间休息 —— 120s ›」（绿色数字），点击弹出 `RestSettingSheet`：
- `Stepper(value:in: 15...600, step: 15)` + 45/60/90/120/180 快捷芯片；
- 每次改动立即 `store.restSeconds = value`，Store 内部 clamp 15…600 并 `save()`，
  不新增任何存储字段，杀掉 App 重开仍保持。

### 3. RestTimer.finish() 增加取消排队通知
前台 tick 可能比通知触发早几十毫秒判定归零；不取消的话，稍后一进后台会再弹一条「休息结束」。
skip / start 原本就各自 cancelNotification()，本轮补齐 finish 这一处。

### 现状核查（第 0 步）
- 训练主页圆圈本来就是 `rest.progress` 驱动（`RestRing`），且只在 `rest.isRunning` 时出现 → 情形 A，只改色；
- 三处「完成一组」入口（训练页 / 播放页训练卡 / TrainingSheet）都已在记录后 `rest.start(seconds: store.restSeconds)`；
- 三处休息卡都有 +30 / 跳过，行为一致；
- 结束提醒已有：系统音 + 震动 + `UINotificationFeedbackGenerator.success`；后台走本地通知；
- 剩余时间一直按 `endDate - now` 计算，回前台按结束时间戳重算；
- 休息中再次「完成一组」：`start()` 会重建 endDate、先取消旧通知、ticker 先停再起，不叠加。

### 已知
- 未在真机验证：CI 只验证编译、包结构、版本号、符号。
- 训练页预设芯片（60/90/120/180）与 Stepper 并存：用 Stepper 设成非预设值（如 45s）时，芯片不高亮。
- 播放页训练卡里的「\(restSeconds)s」小按钮仍是「点一下立刻开始休息」，不是设置入口。
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
        "name": "REPS 4.9.5 — 组间歇绿色环 · 休息时长可调",
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
