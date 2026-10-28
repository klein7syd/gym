# REPS iOS · 4.0.0

纯 SwiftUI 原生 App（不是网页壳），源码在 `ios/REPS/`，由 GitHub Actions 在 macOS 上编译成未签名 IPA。

---

## 一、装到手机上

**下载（免登录直链）**

```
https://github.com/klein7syd/gym/releases/download/v4.0.0/REPS-4.0.0-unsigned.ipa
```

Release 页：https://github.com/klein7syd/gym/releases/tag/v4.0.0

**签名（Windows 上用 Sideloadly）**

1. iTunes 必须装 **Apple 官网版**（Microsoft Store 版找不到设备）
2. Sideloadly 拖入 IPA → 填 Apple ID → Start
3. 开了双重认证的，密码栏填**专用密码**，不是登录密码
4. 手机：设置 → 通用 → VPN与设备管理 → 信任你的证书
5. iOS 16+ 还要在「隐私与安全性」打开**开发者模式**，重启

免费账号签的包 **7 天过期**，到期重签。**重签时别先卸载 App**——一卸载沙盒里的训练记录和身体数据就没了。

---

## 二、这一版做了什么

### 1. 底部栏回归系统原生

`TabView` + `.tabItem`，底层就是 `UITabBar`。没有自绘、没有假胶囊。

编译用的是 **Xcode 26.6 / iOS 26.5 SDK**，所以在你手机上它会自动套用系统的液态玻璃外观，是系统画的，不是仿的。

### 2. 音乐可以真的在 App 里播

| 环节 | 实现 |
|---|---|
| 搜索 | `ITunesAPI` → `itunes.apple.com/search`，无需授权、无需 entitlement |
| 播放 | `MusicHub`（单例）→ `AVPlayer` |
| 播放页 | `NowPlayingView` 全屏，大封面 + 可拖进度 + 上一首/下一首 |
| 常驻 | `MiniPlayerBar` 挂在 `safeAreaInset(.bottom)` |
| 锁屏 | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` |
| 本地音乐 | 导入到 `Documents/Music`，整首播放、永久保存 |

**为什么曲库只能听 30 秒**：那是 Apple 官方试听片段。整首播放要走 MusicKit，需要 `com.apple.developer.musickit` entitlement（付费开发者账号 + 苹果审核），自签名必然拿不到——所以这一版不做虚假承诺，把能做的做到位：搜索、列表、选歌、播放、暂停、拖动、切歌全在 App 内闭环，需要整首时再长按跳 Apple Music。

网易云没有开放第三方播放接口，只提供 `orpheus://` 深链唤起官方 App。

### 3. 身体数据可按日期补记

「我的」→「记录身体数据」：系统 `DatePicker` 选任意过去日期，填体重/体脂，保存即落点。最近 6 条可长按修改、设为曲线第 1 天、删除。

曲线横轴是**健身第几天**（从 `startDate` 起算），体重/体脂/去脂体重/FFMI 共用一张图，各自量程，左轴第一条、右轴第二条。

---

## 三、开发要点

- **最低系统 iOS 16.0**（用到 `NavigationStack`、`scrollDismissesKeyboard`）
- 数据落在 `Documents/reps.json`，导出/导入走 `我的 → 数据`
- 休息计时用绝对时间戳，回到前台自动校准；锁屏提醒走本地通知
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
    ├── MusicHub.swift          播放中枢（本地 + 试听，锁屏控制）
    ├── MusicServices.swift     iTunes 曲库搜索 + 网易云深链
    ├── RestTimer.swift         组间计时 + 本地通知
    ├── TrainView.swift         训练
    ├── MusicView.swift         音乐 + 迷你播放条 + 全屏播放页
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
| 选 Xcode 脚本报错 | runner 上有不带版本号的 `Xcode.app`，正则取不到 | 改成纯 shell 比较版本号 |
| `remove(atOffsets:)` 找不到 | 它来自 SwiftUI 对集合的扩展 | `MusicHub` 补 `import SwiftUI` |
| 搜索后跳走就没了 | 3.0 用 MusicKit 搜，没 entitlement 必然失败 | 换 iTunes 公开接口 |
| 键盘收不起来 | 数字键盘没有回车键 | 滑动收 + 键盘「完成」+ 导航栏「收起」 |

---

## 五、版本对照

| | 1.0 网页壳 | 2.0 原生 | 3.0 液态玻璃 | 4.0 |
|---|---|---|---|---|
| 底部栏 | 系统 TabView | 系统 TabView | 自绘悬浮胶囊 | **系统 TabView（iOS 26 SDK 编译）** |
| 音乐 | 仅本地 | 仅本地 | 搜索后跳转（空壳） | **App 内搜索 + 播放页 + 锁屏** |
| 身体数据 | 无 | 只有动作 1RM | 按当天自动落点 | **可按任意日期补记** |
