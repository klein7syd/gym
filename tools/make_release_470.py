import json, os, urllib.request

tok = os.environ['REPS_TOKEN']
body = {
    'tag_name': 'v4.7.0',
    'target_commitish': 'main',
    'name': 'REPS 4.7.0 — 搜索不截断 · 播放页对齐 · 下拉回菜单 · 训练面板 · 列表可拖动',
    'body': '''## 4.7.0

### 搜索页
- 去掉页面顶部那张「正在播放」卡片、去掉「已连接」授权卡，只在没授权时留一行提示。
- 去掉所有「完整播放」字样（现在库里搜到的本来就能整首放）。
- **结果不再截断**：原来最多 60 条，现在资料库里匹配多少显示多少（`limit = 0` 表示不限制）。
- 结果版式照 Apple Music：上面「专辑」两列网格（封面 / 专辑名 / 艺人·年份），点进去是整张专辑
  的完整曲目（不只是命中的那几首）；下面「歌曲」列表直接点播。

### 播放页对齐
- 歌名、进度条、控制排、音量条全部对齐到**封面的左右边线**（`pad = max(24, (宽 - 封面) / 2)`），
  不再是各自一套留白。
- 竖向节奏统一：封面→标题 26、标题→进度 20、进度→控制 22、控制→音量 16。

### 下拉退回的动效
- 播放页不再是独立窗口层，改成根视图里的一张卡片：底下 TabView 跟着下拉进度
  **实时放大、变亮、圆角收小**（`pull` 0→1），松手过阈值才真正关闭 —— 就是「渐渐回到上一级」。
- 拖动时播放页自身圆角从 0 长到 34，不会露出大片黑边。

### 训练
- 点播放页的训练卡直接打开训练面板（`sheet`，默认 large，可下拉到 medium）。
- 训练卡整体加高：竖向内边距 12→15、休息环 50→56、动作名 16→17、按钮 52×26→54×29。
- 按钮从上到下：`+30`（或休息秒数）→ **完成** → 跳过。点「完成」记一组并自动开始休息。

### 播放列表
- 不要先点「排序」了：进入就是排序状态，右侧把手常驻，**任意一行直接上下拖动**即可改顺序，
  松手即时生效（重建系统队列并续上原来的播放位置）；点一下仍然是跳到那首。

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
