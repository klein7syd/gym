import json, os, urllib.request, urllib.error

tok = os.environ.get('REPS_TOKEN')
if not tok:
    raise SystemExit('no token')

body = {
    'tag_name': 'v4.4.0',
    'target_commitish': 'main',
    'name': 'REPS 4.4.0 — 封面全局可用 · 播放不卡 · 搜索打分+拼音 · 玻璃粗条',
    'body': '''## 4.4.0

### 1. 专辑封面，所有位置都有
之前只有全屏播放页有封面，迷你播放条 / 正在播放卡片 / 播放列表全是灰图标 ——
因为那几个位置只认网络图地址（`artworkURL`），而资料库曲目根本没有这个地址。

现在统一走 `ArtworkStore`：按 `persistentID` 从 `MPMediaItem` 取真实封面，
带内存缓存 + 后台解码，列表滚动时预取前 12 张。

### 2. 点播放不再卡
两处卡顿根源都拔掉了：
- `setQueue` / `nowPlayingItem` / `play` 是跨进程调用，一次几百毫秒，以前整套在主线程同步跑。
  现在界面状态先就位（点下去立刻有反应），系统队列丢后台串行队列；队列没变就不重建。
- 0.1 秒轮询一次读四个 XPC 属性 = 每秒 40 次跨进程调用。现在 0.1 秒只在本地外推时间，
  0.5 秒才跟系统对一次账，偏差小于 0.35 秒不纠。

### 3、6. 搜索重做：打分 + 拼音
- 多关键词是 **AND**：输入「周杰伦 稻香」必须两个词都命中
- 每个词分别打分：歌名完全等于 100 / 歌名里某词等于 92 / 歌名前缀 88 / 歌名包含 74 /
  艺人 64 起 / 专辑只有 32（最容易出噪音，权重压到底）
- **相关性下限**：有强命中时，纯靠专辑名擦边命中的结果直接丢掉
- **拼音**：`qt` → 晴天，`qingtian` → 晴天，`zhoujielun` → 周杰伦

### 4、5. 进度条 / 音量条 + 播放页
- 两个条从 4pt 加粗到 **8pt**，做成白灰玻璃质感：浅灰半透明轨道、白色（深色模式）/
  近黑（浅色模式）已播放段、0.5pt 高光描边 + 轻微外发光，没有圆点把手
- 播放页完全按 Apple Music 排：抓手 → 收起 / 正在播放 / 更多 → 封面（圆角 8，重投影）→
  歌名 20 粗左对齐 → 艺人 20 灰左对齐 → 进度（8pt）→ 时间 → 控制排 → 音量 → 训练卡
- Apple Music 底部那排（歌词 / 待播 / AirPlay）位置留给训练状态

### 已知限制
- 整首播放仍要求歌已在 Apple Music「资料库」（自签没有 MusicKit entitlement）
- 音量条只能改系统音量，系统音量本身是 16 级，条子连续但响度是跳的
- 未在真机验证，CI 只验证了编译与包结构'''
}

req = urllib.request.Request(
    'https://api.github.com/repos/klein7syd/gym/releases',
    data=json.dumps(body).encode(),
    method='POST',
    headers={'Authorization': 'Bearer ' + tok,
             'Accept': 'application/vnd.github+json',
             'Content-Type': 'application/json'})
try:
    r = urllib.request.urlopen(req)
    d = json.load(r)
    print('release id', d['id'], d['tag_name'])
    open('/tmp/relid.txt', 'w').write(str(d['id']))
except urllib.error.HTTPError as e:
    print('ERR', e.code, e.read().decode()[:500])
