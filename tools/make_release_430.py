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
    "## 4.3.0",
    "",
    "### 搜索：只搜你自己的资料库",
    "- 去掉 iTunes 曲库搜索，搜索框现在直接搜 Apple Music 资料库索引，本地实时出结果，不联网。",
    "- 因此**搜到的每一首都能整首完整播放**，会员身份直接生效，不会再有 30 秒试听。",
    "- 也不再有「搜出一堆不搭边的歌」：排序是 歌名前缀 → 歌名包含 → 艺人 → 专辑，且全部来自你的库。",
    "",
    "### 点哪首放哪首",
    "- 曲目改用 persistentID 精确寻址（以前是拿「歌名+艺人」去资料库猜，猜偏了就放成同名翻唱或别的版本）。",
    "- 队列就是你当前看到的搜索结果，下标一一对应。",
    "",
    "### 进度条 / 音量条",
    "- 去掉拖动时那个圆点，就是一条线。",
    "- 进度从 0.4 秒一跳改成 0.1 秒一次：1pt 1pt 地走，不再有台阶感。",
    "- seek 之后 0.9 秒内不采信系统播放器回报的旧时间，松手不会再往回跳；系统没落位会自动补一次。",
    "- 系统自己切歌时同步封面与时长，界面不会停在上一首。",
    "",
    "### 说明",
    "- 搜索范围是资料库，所以想听库里没有的歌，仍然要先去 Apple Music 点「+」加进资料库。",
    "- 未在真机验证，CI 只验证了编译与包结构。",
]

payload = {
    "tag_name": "v4.3.0",
    "target_commitish": "main",
    "name": "REPS 4.3.0 — 只搜资料库 · 点哪首放哪首 · 进度平滑",
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
