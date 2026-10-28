import json
import os
import subprocess
import urllib.request

cwd = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

tok = subprocess.check_output(
    ["bash", "-lc",
     "printf 'protocol=https\\nhost=github.com\\n\\n' | git credential fill | sed -n 's/^password=//p'"],
    cwd=cwd,
).decode().strip()

body_lines = [
    "## 4.2.0",
    "",
    "### 音乐页拆成两个界面",
    "- 顶部新增分段控件：`Apple Music` / `本地`。",
    "- Apple Music 页：搜索框查曲库、授权卡、当前曲目卡片、搜索空态提示。",
    "- 本地页：导入入口（一整条按钮）+ 本地列表 + 沙盒存放说明；搜索框在本地页变成过滤本地歌曲。",
    "- 两个页面各自只显示相关内容的当前播放卡片，不再混在一起。",
    "",
    "### 播放页照 Apple Music 版式重做",
    "- 顶部抓手 + 左收起 + 右更多。",
    "- 封面占满宽度（最大 336），圆角 10、柔和投影。",
    "- 歌名 22 粗体、艺人 18 灰色，**左对齐**贴着封面左边（Apple Music 就是这个对齐方式）。",
    "- 进度条 5pt 细条，下面左「已播放」右「-剩余」。",
    "- 控制排：播放列表 / 上一首 / 播放（42pt 纯图标，无圆形底）/ 下一首 / 循环，位置与 Apple Music 五图标一致。",
    "- 音量细条保留，与侧边键同步。",
    "- 底部原来放歌词/待播/AirPlay 的那一排，换成训练状态卡：动作、第几组、上一组重量×次数、休息环 +30/跳过。",
]

payload = {
    "tag_name": "v4.2.0",
    "target_commitish": "main",
    "name": "REPS 4.2.0 — 音乐双界面 · 播放页照抄 Apple Music",
    "body": "\n".join(body_lines),
}

req = urllib.request.Request(
    "https://api.github.com/repos/klein7syd/gym/releases",
    data=json.dumps(payload).encode(),
    method="POST",
    headers={
        "Authorization": "Bearer " + tok,
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    },
)
try:
    d = json.load(urllib.request.urlopen(req))
    print("release id", d["id"], d["tag_name"])
except urllib.error.HTTPError as e:
    print("ERR", e.code, e.read().decode()[:500])
