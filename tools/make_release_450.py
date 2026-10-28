import json, os, urllib.request

tok = os.environ['REPS_TOKEN']
body = {
    'tag_name': 'v4.5.0',
    'target_commitish': 'main',
    'name': 'REPS 4.5.0 — 搜索按专辑排版 · 灰色液态玻璃播放页 · 封面比例',
    'body': '''## 4.5.0

### 搜索结果改成按专辑排版
- 一条专辑一组：左边专辑封面、专辑名、`艺人 · N 首`，右边一个「播放全部」按钮。
- 组内曲目按碟号 + 音轨号排序，每行带音轨号，不再是一大串看不出归属的散歌。
- 没有专辑名的散装单曲统一归到「未知专辑」，不会一首一个标题栏。
- 顶部统计改成 `我的资料库 · N 首 · M 张专辑 · 全部可完整播放`。
- 队列仍是整串结果，点组内任意一首从那儿接着放，persistentID 精确寻址，不会串歌。

### 播放页：灰色液态玻璃
- 背景换成 `灰底(0.13) + ultraThinMaterial + 中性柔光 + 薄白涂层`，只有灰度没有色相，不会发蓝发紫。
- 整页固定深色（`.environment(.dark)` + `.preferredColorScheme(.dark)`），浅色系统下也一致，状态栏图标自动转白。
- 进度条 / 音量条从黑色改为白色：97% 白填充、0.5pt 高光描边、轻微白色外发光；轨道提到 22% 白，在白底上也能看清。

### 封面按 Apple Music 比例
- 从「屏宽 - 32、上限 352」改成「屏宽 × 0.76、上限 320、最小 130」。
- 393pt 宽机型上约 299pt（原来是 361→352），两侧留白更接近 Apple Music。

### 已知限制
- 整首播放仍要求歌已在 Apple Music「资料库」（自签没有 MusicKit entitlement）。
- 系统音量仍只有 16 级（`MPVolumeView` 内部 UISlider 的固有限制）。
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
    open('/tmp/relid.txt', 'w').write(str(d['id']))
except urllib.error.HTTPError as e:
    print('ERR', e.code, e.read().decode()[:400])
