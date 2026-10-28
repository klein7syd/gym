import json, os, urllib.request

tok = os.environ['REPS_TOKEN']
body = {
    'tag_name': 'v4.6.0',
    'target_commitish': 'main',
    'name': 'REPS 4.6.0 — 专辑网格 · 卡片式播放页 · 训练面板 · 播放列表排序',
    'body': '''## 4.6.0

### 音乐搜索页清理
- 去掉搜索结果上方的「正在播放」大卡片 —— 底部本来就有迷你播放条。
- 去掉「Apple Music 资料库 · 已连接」整块卡片；只有没授权时才留一行提示 + 授权按钮。
- 去掉「全部可完整播放 / 完整版」这类标识（现在每首都是完整播放，标了没意义）。

### 搜索按专辑排版（照 Apple Music）
- 先是「专辑」两列网格：封面、专辑名、`艺人 · 年份`，跟 Apple Music 艺术家页一致。
- **点进专辑能看到整张曲目**（不再只有命中的那几首）——这就是「曲目很多还是没显示」的原因：
  以前只列命中的歌，专辑里没命中的自然看不见。现在专辑详情页从资料库索引里取全量曲目，
  按碟号 + 音轨号排序，带音轨号，顶部有「播放 / 随机播放」两个胶囊按钮。
- 网格下面还有「歌曲」列表，所有命中的歌仍然可以一键直接播。

### 播放页
- 版式重排：统一左边距 24，封面 → 30 → 歌名(22 粗) / 艺人(17) → 26 → 进度条 → 20 → 控制键 → 22 → 音量 → 训练卡，
  封面按屏宽 0.76（上限 322）。
- **不再有黑边**：播放页不再是全屏 cover，而是根视图里的一张卡片 ——
  打开时底部 TabView 缩小到 0.93 并压暗，播放页从底部推上来；往下拖的时候底下的菜单一直看得见，
  拖过阈值收回，就是 iOS 那种「回到上一级」的动效。拖动时页面还会切圆角。
- 背景仍是灰色液态玻璃，整页固定深色，进度 / 音量条是白色。

### 训练
- 训练卡变高，显示休息环、动作名、第几组、上一组。
- 右侧竖排三个按钮：`+30` / **完成** / `跳过`（完成就是记一组并开始组间休息）。
- 点卡片文字区域打开训练面板（sheet，medium/large 两档，平滑滑入）：动作、重量/次数步进、
  完成一组、本次记录（可删）、结束训练。

### 播放列表
- 右上「排序」进入编辑模式，按住右侧把手拖动即可改顺序；当前正在播的那首位置会跟着走，
  系统播放器队列按新顺序重建，并回到原来的播放进度。

### 已知限制
- 整首播放仍要求歌已在 Apple Music「资料库」（自签没有 MusicKit entitlement）。
- 系统音量仍只有 16 级（MPVolumeView 内部 UISlider 的固有限制）。
- 未在真机验证，CI 只验证了编译与包结构。'''
}
req = urllib.request.Request(
    'https://api.github.com/repos/klein7syd/gym/releases',
    data=json.dumps(body).encode(), method='POST',
    headers={'Authorization': 'Bearer ' + tok,
             'Accept': 'application/vnd.github+json',
             'Content-Type': 'application/json'})
r = urllib.request.urlopen(req)
d = json.load(r)
print('release id', d['id'], d['tag_name'])
print('upload_url', d['upload_url'])
