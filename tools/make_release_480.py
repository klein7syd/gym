import json, os, urllib.request

tok = os.environ['REPS_TOKEN']
body = {
    'tag_name': 'v4.8.0',
    'target_commitish': 'main',
    'name': 'REPS 4.8.0 — 修黑边/闪烁/专辑颠倒 · 专辑排序 · 播放页比例',
    'body': '''## 4.8.0

### 1. 专辑详情：专辑名与歌手名颠倒
Apple Music 的规范是**专辑名是大字**、艺人是下面小字。上一版把 `displayArtist` 放在 21pt 粗体、
专辑名放在 13pt 灰字，正好反了。现在：专辑名 21pt 粗 → 「艺人 · 年份」13pt 灰 → 曲目数。

### 2. 点播放时的「色块闪烁」
两个来源一起修掉：
- **封面占位块是彩色的**：资料库曲目在封面解码完成前显示的是按歌名哈希取色的彩色方块，
  在播放页那是一块 300pt 的纯色，翻歌时整块颜色变一次 —— 就是你看到的「莫名其妙的色块」。
  现在资料库曲目一律中性灰（20% 白）占位 + 淡入，本地无内嵌封面的才用彩色。
- **整个 App 的主题在被看见的时候切换**：播放页原来写死 `.preferredColorScheme(.dark)`，
  在播放页还在滑入、菜单露在外面那 0.4 秒里，整个窗口会从浅色翻成深色，看起来就是一整块颜色闪。
  现在改成「播放页完全盖住之后才切深色、开始下滑之前就切回来」，两次切换都发生在被遮住的时候。

### 3. 重大 Bug：播放页上下大黑边
播放页自己 `.clipShape` 圆角裁切，而它当时只在**安全区**内布局，于是裁切边界卡在状态栏下沿和
底部横条上沿 —— 上下各留一条纯黑。现在播放页 `ignoresSafeArea()` 铺满整屏，
再用 `SafeArea.insets` 把内容往里让，圆角裁切覆盖到屏幕边缘，黑边没了。
顺手让封面、标题区也能往下划收回（以前只有抓手和顶栏能划）。

### 4. 专辑排序：本艺人的正式录音室专辑优先
`albums(from:matching:)` 新增打分排序（分越小越靠前）：
- 专辑艺人里包含你搜的词 → −1000（本人的专辑优先，feature 只出现的别人专辑往后）
- 合辑 / Various Artists → +400
- 曲目 ≥5 → −60、≥10 → −40；≤2（单曲/EP）→ +40
- 同年份里新专略前

### 5. 播放页比例放大
- 铺满整屏后封面按**屏宽 82%**、上限 340（原来 76% / 322）；
- 竖向节奏收成 24 / 20 / 18 / 18，把省下的高度全给封面；
- 歌名 22→24、艺人 17→18、时间 11→12，控制排整体放大（播放键 42→48、上一首/下一首 27→30、
  列表与循环 19→21），音量图标 10→12。

### 6. 训练卡：字号跟上器皿
上一版只把卡片放大、字号没动。现在：动作名 17→20、状态 11→12、副行 11→12、
休息环 56→62、按钮 54×29→64×31、字 11→13，按钮间距调到 6。

### 已知限制
- 整首播放要求歌已在 Apple Music「资料库」（自签没有 MusicKit entitlement）。
- 系统音量仍是 16 级（`MPVolumeView` 内部 UISlider 的固有限制）。
- 未在真机验证，CI 只验证了编译与包结构。'''
}
req = urllib.request.Request(
    'https://api.github.com/repos/klein7syd/gym/releases',
    data=json.dumps(body).encode(), method='POST',
    headers={'Authorization': 'Bearer ' + tok,
             'Accept': 'application/vnd.github+json',
             'Content-Type': 'application/json'})
try:
    r = urllib.request.urlopen(req)
    d = json.load(r)
    print('release id', d['id'], d['tag_name'])
except urllib.error.HTTPError as e:
    print('ERR', e.code, e.read().decode()[:400])
