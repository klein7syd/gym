# REPS iOS · 4.3.0

纯 SwiftUI 原生 App（不是网页壳），源码在 `ios/REPS/`，由 GitHub Actions 在 macOS 上编译成未签名 IPA。

---

## 一、装到手机上

**下载（免登录直链）**

```
https://github.com/klein7syd/gym/releases/download/v4.3.0/REPS-4.3.0-unsigned.ipa
```

Release 页：https://github.com/klein7syd/gym/releases/tag/v4.3.0

**签名（Windows 上用 Sideloadly）**

1. iTunes 必须装 **Apple 官网版**（Microsoft Store 版找不到设备）
2. Sideloadly 拖入 IPA → 填 Apple ID → Start
3. 开了双重认证的，密码栏填**专用密码**，不是登录密码
4. 手机：设置 → 通用 → VPN与设备管理 → 信任你的证书
5. iOS 16+ 还要在「隐私与安全性」打开**开发者模式**，重启

免费账号签的包 **7 天过期**，到期重签。**重签时别先卸载 App**——一卸载沙盒里的训练记录和身体数据就没了。

---

## 二、这一版做了什么

### 1. 音乐：只搜资料库，全部完整播放

| 环节 | 实现 |
|---|---|
| 搜索 | 直接查自建的资料库索引（`AppleMusicService.search`），本地实时出结果，不联网 |
| 播放 | `MPMusicPlayerController.applicationMusicPlayer`，整首完整播放 |
| 定位 | `persistentID` 精确寻址，点哪首放哪首，不会放成同名翻唱 |
| 本地音乐 | 导入到 `Documents/Music`，整首播放、永久保存 |

4.3 之前是「iTunes 曲库搜 + 资料库匹配」，匹配不上的歌只能 30 秒试听，还会搜出资料库外的结果 —— 现在这条路整个去掉了：**搜索范围就是你的资料库，搜到的每一首都能整首放**。想听库里没有的歌，去 Apple Music 点个「+」加进资料库即可。

为什么不用 MusicKit 直接放曲库任意歌曲：需要 `com.apple.developer.musickit` entitlement，只有付费开发者账号能勾选，Sideloadly 自签一定没有。MediaPlayer 这条路只需要 `NSAppleMusicUsageDescription`，自签也能用。

**为什么不用 MusicKit**：整首播放曲库任意歌曲需要 `com.apple.developer.musickit` entitlement，只有付费开发者账号在 Developer Portal 勾选后才能拿到。Sideloadly 自签的包一定没有它，调 MusicKit 必然失败——上一版的「空壳」就是这么来的。

**实际能听到什么**：已订阅 Apple Music、且这首歌在你「资料库」里（Apple Music 里点过 `+`），就能在 App 内整首播放。搜索结果的每一行会标 `完整` / `试听` / `不可播`，播放页顶部标 `APPLE MUSIC 完整版`，不放空话。

资料库匹配是规范化的：`稻香 (Live)`、`稻香 - Remastered`、`Song feat. XX` 都能对上资料库里的 `稻香` / `Song`。

### 2. 音乐页：Apple Music / 本地 两个界面

顶部一个分段控件切换，两个来源彻底分开：

| 界面 | 内容 |
|---|---|
| Apple Music | 搜索框查曲库、授权状态卡、当前曲目卡片、搜索空态提示 |
| 本地 | 导入入口（整条按钮）、本地歌曲列表、沙盒存放说明 |

搜索框跟着界面走：在本地页输入关键词就是过滤本地歌曲，不会去搜网络。

### 3. 播放页照 Apple Music 版式重做

- 顶部抓手 → 左收起 → 右更多
- 封面占满宽度（最大 336），圆角 10，柔和投影
- 歌名 22 粗体、艺人 18 灰色，**左对齐**贴封面左边（Apple Music 就是这个对齐）
- 进度条 5pt 细条，下面左边「已播放」右边「-剩余」
- 控制排：播放列表 / 上一首 / 播放（42pt 纯图标，无圆形底）/ 下一首 / 循环
- 音量细条保留，拖动仍是真实系统音量
- Apple Music 底部那排歌词 / 待播 / AirPlay 整排去掉，换成训练状态卡（动作、第几组、上一组重量×次数、休息环 +30/跳过）


- **进度条 / 音量条都是自绘细条**（`SlimBar`）：就是一条线，没有圆点把手，按住任意位置拖动（命中区 18pt）。进度 0.1 秒推一次，1pt 1pt 走，不是台阶
- **时间显示**：`已播放 / -剩余`，跟 Apple Music 一致
- **顶部**：左侧收起、中间「正在播放」、右侧更多，三者居中对齐，去掉了两行叠字和玻璃圆底
- **封面**：按剩余高度自适应（最大 336），下面歌名 / 进度 / 控制 / 音量沿中轴排，间距 10–14pt，音量条与底部训练条之间不再留大片空白
- **音量条**：拖动的是设备真实系统音量（`MPVolumeView` 内部 `UISlider` 读写），和侧边键完全同步；iOS 不允许直接改 `outputVolume`
- **循环方式**：三态，不循环 → 列表循环 → 单曲循环，与系统播放器 `repeatMode` 双向同步
- **播放列表**：当前队列全量列出，点歌直接跳，当前项高亮
- **底部训练状态**：当前动作、第几组、上一组「重量 × 次数」、休息倒计时环 + `+30` / `跳过`——数据源就是训练页那个 `RestTimer`，两边永远一致

### 4. 视觉：全局去掉渐变

页面底色改成纯色 `systemGroupedBackground`（原来有三团蓝绿紫柔光）；玻璃卡片的填充和描边都改成单色；折线图区域填充改成 12% 半透明纯色；没有封面时的占位图也从渐变改成纯色。整页不再发灰发紫。

### 5. 底部栏系统原生

`TabView` + `.tabItem`，底层就是 `UITabBar`。编译用 **iOS 26.5 SDK**，所以在手机上自动套用系统的液态玻璃外观，是系统画的，不是仿的。

### 6. 身体数据可按日期补记

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

| | 1.0 网页壳 | 2.0 原生 | 3.0 液态玻璃 | 4.0 | 4.1 |
|---|---|---|---|---|---|
| 底部栏 | 系统 TabView | 系统 TabView | 自绘悬浮胶囊 | 系统 TabView | 系统 TabView |
| 音乐 | 仅本地 | 仅本地 | 搜索后跳转（空壳） | 搜索 + 30 秒试听 | **资料库曲目完整播放** |
| 播放页 | 无 | 无 | 无 | 封面 + 进度 + 切歌 | **+ 音量 / 循环 / 列表 / 训练状态** |
| 身体数据 | 无 | 只有动作 1RM | 按当天自动落点 | 可按任意日期补记 | 可按任意日期补记 |

---

## 六、已知限制（说清楚，不糊弄）

1. **完整播放依赖资料库**。歌不在 Apple Music 资料库（没点过 `+`）就只能 30 秒试听。这是 sideload 签名缺 MusicKit entitlement 的硬限制。
2. **未在真机验证**。CI 只证明「编译通过 + 包结构正确」，键盘收起、锁屏计时、完整播放这些都要你装上后实测。
3. 网易云没有开放第三方播放接口，只能 `orpheus://` 唤起官方 App。
