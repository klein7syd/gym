import json
import os
import subprocess
import urllib.request

tok = subprocess.check_output(
    ["bash", "-lc",
     "printf 'protocol=https\\nhost=github.com\\n\\n' | git credential fill | sed -n 's/^password=//p'"],
    cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
).decode().strip()

body_lines = [
    "## 4.1.1",
    "",
    "### 视觉：全局去掉渐变",
    "- 页面底色改纯色 systemGroupedBackground，不再有蓝绿紫三团柔光。",
    "- 玻璃卡片的填充与描边都改成单色，不再是明暗渐变。",
    "- 折线图区域的渐变填充改成 12% 半透明纯色；无封面时的占位封面也改纯色。",
    "",
    "### 播放页：按 Apple Music 重排",
    "- 进度条、音量条换成自绘 4pt 细条：静态时只有一条线，按住拖动时把手才浮出来（12pt 圆点），",
    "  点哪儿跳哪儿，命中区域仍有 18pt 高。",
    "- 进度条下面的时间改成「已播放 / -剩余」。",
    "- 顶部收敛成左侧收起、中间正在播放、右侧更多，去掉两行叠字和玻璃圆底，居中对齐。",
    "- 封面按剩余高度自适应（最大 336），歌名/进度/控制/音量沿中轴排，间距 10-14pt，",
    "  音量条与底部训练条之间不再留大片空白。",
    "- APPLE MUSIC 完整版 标识降为歌名下的绿色小字。",
    "- 音量条拖动仍是真实系统音量（MPVolumeView 内部 UISlider 读写），和侧边键同步。",
    "",
    "### 已知限制",
    "- 完整播放依旧要求歌已在 Apple Music 资料库（自签没有 MusicKit entitlement）。",
    "- 未在真机验证，CI 只验证了编译与包结构。",
]

payload = {
    "tag_name": "v4.1.1",
    "target_commitish": "main",
    "name": "REPS 4.1.1 — 去渐变 · 细条控件 · 播放页重排",
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
    with open("/tmp/relid.txt", "w") as f:
        f.write(str(d["id"]))
except urllib.error.HTTPError as e:
    print("ERR", e.code, e.read().decode()[:500])
