# REPS iOS · 4.4.0

纯 SwiftUI 原生 App（不是网页壳），源码在 `ios/REPS/`，由 GitHub Actions 在 macOS 上编译成未签名 IPA。

---

## 一、装到手机上

**下载（免登录直链）**

```
https://github.com/klein7syd/gym/releases/download/v4.4.0/REPS-4.4.0-unsigned.ipa
```

Release 页：https://github.com/klein7syd/gym/releases/tag/v4.4.0

**签名（Windows 上用 Sideloadly）**

1. iTunes 必须装 **Apple 官网版**（Microsoft Store 版找不到设备）
2. Sideloadly 拖入 IPA → 填 Apple ID → Start
3. 开了双重认证的，密码栏填**专用密码**，不是登录密码
4. 手机：设置 → 通用 → VPN与设备管理 → 信任你的证书
5. iOS 16+ 还要在「隐私与安全性」打开**开发者模式**，重启

免费账号签的包 **7 天过期**，到期重签。**重签时别先卸载 App**——一卸载沙盒里的训练记录和身体数据就没了。

---

## 二、这一版做了什么

### 1. 专辑封面：所有位置都是真封面

之前只有全屏播放页有封面，迷你播放条、正在播放卡片、播放列表全是灰色占位图。
原因是那几个位置只认网络图地址（`artworkURL`），而资料库曲目根本没有这个地址。

现在统一走 `ArtworkStore`：按 `persistentID` 从 `MPMediaItem` 取真实封面，内存缓存 + 后台解码，
列表出现时预取前 12 张。所有位置（列表行、迷你条、正在播放卡、播放列表、全屏页）共用这一份。

### 2. 点播放不再卡一大下

两个根源都拔掉了：

| 卡顿来源 | 原因 | 现在 |
|---|---|---|
| 设系统队列 | `setQueue` / `nowPlayingItem` / `play` 都是跨进程调用，一次几百毫秒，以前整套在主线程同步跑 | 界面状态先就位（点下去立刻有反应），系统队列丢后台串行队列；队列没变就不重建 |
| 0.1 秒轮询 | 每 0.1 秒读 4 个 XPC 属性 = 每秒 40 次跨进程调用，全压主线程 | 0.1 秒只在本地外推时间，0.5 秒才跟系统对一次账，偏差 < 0.35 秒不纠 |

另外封面以前是主线程同步解码 600×600 的图，现在也在后台，取到后自动刷新。

### 3. 搜索：打分 + 拼音

| 机制 | 说明 |
|---|---|
| 多词 AND | 输入「周杰伦 稻香」必须两个词都命中，不再「沾一个词就算」 |
| 分档打分 | 歌名完全等于 100 · 歌名里某词等于 92 · 歌名前缀 88 · 歌名包含 74 · 艺人 64 起 · 专辑只有 32 |
| 相关性下限 | 有强命中时，纯靠专辑名擦边命中的结果直接丢掉（就是之前那堆「无关的歌」） |
| 拼音 | `qt` → 晴天，`qingtian` → 晴天，`zhoujielun` → 周杰伦；索引在后台建时算好，不拖慢输入 |

搜索范围仍然只有你自己的资料库，搜到的每一首都能整首播放（会员身份直接生效）。
为什么不用 MusicKit：整首播放曲库任意歌曲需要 `com.apple.developer.musickit` entitlement，
只有付费开发者账号能勾选，Sideloadly 自签一定没有。MediaPlayer 这条路只需要
`NSAppleMusicUsageDescription`，自签也能用。

### 4. 进度条 / 音量条：8pt 白灰玻璃

- 从 4pt 加粗到 **8pt**，命中区 26pt
- 轨道是浅灰半透明玻璃槽，已播放段白色（深色模式）/ 近黑（浅色模式），
  0.5pt 高光描边 + 轻微外发光
- 没有圆点把手，按住任意位置拖动，点哪儿跳哪儿
- 音量条拖的仍是真实系统音量（`MPVolumeView` 内部 `UISlider`），和侧边键同步

### 5. 播放页：照 Apple Music 排

```
        ── 抓手 ──
⌄        正在播放        ⋯
     [    封面    ]        圆角 8，重投影
歌名（20 粗，左对齐）
艺人（20 灰，左对齐）
═════ 进度条 8pt ═════
0:12              -3:20
☰   ⏮   ▶   ⏭   🔁
🔈 ═══ 音量 ═══ 🔊
[ Apple Music 那排歌词/待播/AirPlay → 训练状态 ]
```

底部训练状态：当前动作、第几组、上一组「重量 × 次数」、休息倒计时环 + `+30` / `跳过`，
数据源就是训练页那个 `RestTimer`，两边永远一致。

### 6. 视觉：全局去掉渐变

页面底色改成纯色 `systemGroupedBackground`（原来有三团蓝绿紫柔光）；玻璃卡片的填充和描边都改成单色；折线图区域填充改成 12% 半透明纯色；没有封面时的占位图也从渐变改成纯色。整页不再发灰发紫。

### 7. 底部栏系统原生

`TabView` + `.tabItem`，底层就是 `UITabBar`。编译用 **iOS 26.5 SDK**，所以在手机上自动套用系统的液态玻璃外观，是系统画的，不是仿的。

### 8. 身体数据可按日期补记

「我的」→「记录身体数据」：系统 `DatePicker` 选任意过去日期，填体重/体脂，保存即落点。最近 6 条可长按修改、设为曲线第 1 天、删除。

曲线横轴是**健身第几天**（从 `startDate` 起算），体重/体脂/去脂体重/FFMI 共用一张图，各自量程，左轴第一条、右轴第二条。

---

## 三、开发要点

- **最低系统 iOS 16.0**（用到 `NavigationStack`、`scrollDismissesKeyboard`）
- 数据落在 `Documents/reps.json`，导出/导入走 `我的 → 数据`
- 休息计时用绝对时间戳，回到前台自动校准；锁屏提醒走本地通知
- 两种播放引擎共用一套对外接口：`.av`（本地/试听，`AVPlayer`）与 `.appleMusic`（完整版，`MPMusicPlayerController`），切换时互相 `stop()`，不会两个声音叠在一起
- 完整版播放时**不写** `MPNowPlayingInfoCenter`——锁屏信息交给系统投送，避免我们覆盖成错误元数据
- 界面样式集中在 `Theme.swift`：`.ultraThinMaterial` + 对角染色 + 1pt 镜面描边 + 柔和外阴影 + 三团模糊色斑背景

```
ios/
├── project.yml                 XcodeGen 配置
├── README.md
└── REPS/
    ├── REPSApp.swift           入口 + 系统 TabView
    ├── Theme.swift             玻璃样式、背景、按钮、键盘栏
    ├── Models.swift            数据模型 + moves.json 解码
    ├── Store.swift             持久化、统计、BMI/BMR/TDEE/FFMI/Navy
    ├── AppleMusicService.swift 资料库授权 + 索引 + 曲目匹配（完整播放）
    ├── MusicHub.swift          播放中枢（AV + 系统播放器双引擎，锁屏控制）
    ├── MusicServices.swift     iTunes 曲库搜索 + 网易云深链
    ├── RestTimer.swift         组间计时 + 本地通知
    ├── TrainView.swift         训练
    ├── MusicView.swift         音乐 + 迷你播放条 + 全屏播放页 + 播放列表 + 音量条
    ├── GrowthView.swift        成长（多指标双轴曲线）
    ├── ProfileView.swift       我的（含按日期补记身体数据）
    └── Resources/moves.json    109 个动作
```

**改代码后重新出包**（Windows 上）

```
python tools/push-via-api.py "说明"
python tools/download-ipa.py
```

本机到 github.com 的 git 传输会被代理挡（CONNECT 502），所以用 API 推、用 API 拉，两个脚本都在 `tools/`。

---

## 四、踩过的坑

| 现象 | 原因 | 处理 |
|---|---|---|
| 打不开工程 | XcodeGen 默认生成 Xcode 16 工程格式 | `projectFormat: xcode15_0` |
| 编译机没有新版 SDK | 默认跑在 macos-14 / Xcode 15.4 | 换 `macos-latest` + 脚本选最高版本 Xcode |
| 选 Xcode 脚本报错 |  runner 上有不带版本号的 `Xcode.app`，正则取不到 | 改成纯 shell 比较版本号 |
| `remove(atOffsets:)` 找不到 | 它来自 SwiftUI 对集合的扩展 | `MusicHub` 补 `import SwiftUI` |
| 搜索后跳走就没了 | 3.0 用 MusicKit 搜，没 entitlement 必然失败 | 换 iTunes 公开接口 |
| 只能听 30 秒 | MusicKit entitlement 自签拿不到 | 改走 `MPMusicPlayerController` + 资料库匹配 |
| 键盘收不起来 | 数字键盘没有回车键 | 滑动收 + 键盘「完成」+ 导航栏「收起」 |
| `playbackDuration` 拆包报错 | 它是非可选 `TimeInterval`，不是 `TimeInterval?` | 直接比较，不写 `if let` |

---

## 五、版本对照

| | 1.0 网页壳 | 2.0 原生 | 3.0 液态玻璃 | 4.1 | 4.3 | 4.4 |
|---|---|---|---|---|---|---|
| 底部栏 | 系统 TabView | 系统 TabView | 自绘悬浮胶囊 | 系统 TabView | 系统 TabView | 系统 TabView |
| 音乐搜索 | 仅本地 | 仅本地 | 搜索后跳转（空壳） | 30 秒试听 | 只搜资料库 | **打分 + 相关性门限 + 拼音** |
| 播放 | — | 本地文件 | — | 资料库完整播放 | persistentID 精确寻址 | 后台设队列，不卡 |
| 封面 | — | — | — | 只有全屏页有 | 只有全屏页有 | **所有位置都有** |
| 播放页 | 无 | 无 | 无 | 音量 / 循环 / 列表 / 训练状态 | 细条 + 重排 | **8pt 白灰玻璃条，照 Apple Music 排** |
| 身体数据 | 无 | 只有动作 1RM | 按当天自动落点 | 可按任意日期补记 | 可按任意日期补记 | 可按任意日期补记 |

---

## 六、已知限制（说清楚，不糊弄）

1. **整首播放依赖资料库**。歌不在 Apple Music 资料库（没点过 `+`）就在这里搜不到也放不了。这是 sideload 签名缺 MusicKit entitlement 的硬限制——不是没做，是拿不到授权。
2. **系统音量只有 16 级**。音量条画的是连续值、跟手指走，但实际响度是 16 级跳的（iOS 不开放连续设音量，只能借 `MPVolumeView` 内部的 `UISlider`）。
3. **未在真机验证**。CI 只证明「编译通过 + 包结构正确」，封面加载速度、点播放的响应、拼音搜索命中率都要你装上后实测。
4. 网易云没有开放第三方播放接口，只能 `orpheus://` 唤起官方 App。
