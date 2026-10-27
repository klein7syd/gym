# REPS iOS 版（WKWebView 原生壳）

这套东西的作用：把 `fitness-app/` 那套网页原封不动装进一个真正的 iOS App 里，
产出 `.ipa`，你自己签名装到 iPhone 上。

**网页代码一行没改。** 以后改了网页，重跑一次流水线，出的就是新版。

---

## 当前状态（2026-10-28）

| 项 | 状态 |
|---|---|
| 云端编译 | ✅ 跑通（GitHub Actions / macos-14 / Xcode 15.4，约 5 分钟） |
| 产物 | ✅ `dist/REPS-unsigned.ipa`（148 KB，arm64） |
| 包内容 | ✅ `Web/index.html` + `data/moves.js` + `fonts/press2p.woff2` + 图标都在 |
| Info.plist | ✅ `com.klein7syd.reps`，iOS 15.0+，`UIBackgroundModes=audio`，仅竖屏 |
| 签名安装 | ⬜ 还没在你手机上跑过，需要你用 Sideloadly 签 |

**没验证过的部分**：真机行为（白屏 / 后台音频 / 文件选择器 / localStorage 是否真持久）。
下面每一步都是能编译、能出包，但运行时还没人试过。

---

## 为什么是「壳 + 云端编译」

| 约束 | 解法 |
|---|---|
| 只有 Windows，没有 Mac | 借 GitHub Actions 的 `macos-14` 机器编译 |
| 不会写/不想维护两套 UI | WKWebView 直接加载网页，单一代码源 |
| 要装到自己手机上 | 产出**未签名** IPA，你用 Sideloadly / ESign 签 |

## 目录

```
ios/
├── project.yml                 XcodeGen 工程描述（不手写 .xcodeproj）
├── REPS/
│   ├── AppDelegate.swift       入口 + AVAudioSession（后台音频的前提）
│   ├── WebViewController.swift WKWebView 容器 + 弹窗代理
│   ├── LocalWebServer.swift    本地 HTTP 服务，替代 file://
│   ├── Info.plist              后台音频 / 竖屏 / 启动屏
│   ├── Assets.xcassets/        图标（1024 由 CI 从 fitness-app 生成）
│   └── Web/                    ← CI 运行时把 fitness-app 拷进来，不入库
└── ..
.github/workflows/ios-ipa.yml  云端编译流水线
```

## 两个关键设计（别乱改）

**1. 用本地 HTTP 服务而不是 `file://`**

WKWebView 下 `file://` 源的 `localStorage` 不可靠，杀掉 App 再进可能就空了 ——
而这个 App 的全部训练记录都存在 `localStorage` 里。
`LocalWebServer` 监听固定端口 `127.0.0.1:8787`，把内置的 `Web/` 目录当静态站发出去。
origin 固定 → 数据能长期留存。**端口改了等于换库，数据会「消失」。**

**2. `AVAudioSession.playback` + `UIBackgroundModes: audio`**

这是比 PWA 强的地方：锁屏后 App 不会被系统挂起，
音乐能继续放，网页里的静音保活音轨也还在，计时不会被完全冻结。
（真机首次验证时重点看这一条。）

---

## 三步走

### 第 1 步：代码推到 GitHub

仓库：`https://github.com/klein7syd/gym`（默认分支 `main`）

```bash
cd C:/Users/32077/WorkBuddy/gym
git push -u origin main
```

推上去之后，GitHub 会自动跑 `Build iOS IPA`（也可以去 Actions 页面手动 `Run workflow`）。
整个流程大约 5–10 分钟。

### 第 2 步：下载 IPA

Actions → 最新一次 `Build iOS IPA` → 页面底部 **Artifacts** → 下载 `REPS-unsigned-ipa`
→ 解压得到 `REPS-unsigned.ipa`。

### 第 3 步：Windows 上签名安装

推荐 **Sideloadly**（最省事，直接吃 IPA）：

1. 装 iTunes：**必须**用 Apple 官网版（apple.com/itunes），
   **不要**用 Microsoft Store 版，否则 Sideloadly 找不到设备驱动。
2. 装 Sideloadly：https://sideloadly.io
3. iPhone 用数据线连电脑，手机上点「信任此电脑」。
4. Sideloadly 里：
   - IPA 选 `REPS-unsigned.ipa`
   - Apple ID 填你的（建议单独注册一个，别用主账号）
   - 点 Start，输入密码（如果开了双重认证，要填**专用密码**，不是登录密码）
5. 手机上：设置 → 通用 → VPN与设备管理 → 点你的 Apple ID → 信任
6. iOS 16 及以上还要：设置 → 隐私与安全性 → **开发者模式** → 打开 → 重启手机

就装好了，桌面出现 REPS 图标。

---

## 免费 Apple ID 的限制（必须知道）

| 项 | 免费账号 |
|---|---|
| 有效期 | **7 天**，到期 App 打不开，要重新签一次 |
| 同时装的 App | 最多 3 个 |
| 签名方式 | 每周用 Sideloadly 重签，**覆盖安装，数据不丢** |

> 重签时**不要先卸载 App**，直接用 Sideloadly 覆盖装。
> 一卸载，`localStorage` 里的训练记录就跟着没了。
> 有付费开发者账号（$99/年）就是 1 年有效期，流程完全一样。

## 音乐文件怎么放

App 里的「➕ 添加音乐」走的是系统文件选择器，只能选 **「文件」App 里能看到的音频**。
Apple Music / 流媒体受版权保护，选不了。做法：
用 iTunes 或爱思助手把 mp3 传到「文件」App（或 iCloud Drive），再在 App 里选。
选完的歌是临时引用，**每次重开 App 要重新选一遍** —— 这是网页版的老问题，还没修。

---

## 改完代码怎么推

这台机器（Windows 那台）到 `github.com:443` 的 git 传输被代理挡着，
`git push` 会报 `CONNECT tunnel failed, response 502`。但 `api.github.com` 是通的，
所以走 REST API：

```bash
cd C:/Users/32077/WorkBuddy/gym
git add -A && git commit -m "改了啥"
python tools/push-via-api.py "改了啥"       # 用已保存的 github 凭据，无需额外配置
```

产物下载也走 API：

```bash
python tools/download-ipa.py                # 存到 dist/REPS-unsigned.ipa
```

> 注意：API 建出来的 tree sha 和本地 git 算的不一样，所以远端 commit sha 与本地不同（内容一致）。
> 有网的时候执行 `git fetch origin && git reset --hard origin/main` 就能把本地历史对齐。

## 踩过的坑（都已在配置里绕开）

1. **XcodeGen 默认生成 Xcode 16 的工程格式（objectVersion 77）**，
   macos-14 上的 Xcode 15.4 直接报 `future Xcode project file format (77)`。
   → `project.yml` 里钉死 `projectFormat: xcode15_0`。
2. **`String.split(separator:)` 的 separator 只能是 Character**，
   拿 `"\r\n"` 去切会编译失败 → 换成 `components(separatedBy:)`。
3. **`@main` 在 UIApplicationDelegate 上有版本坑** → 用 `@UIApplicationMain`，稳。
4. **空仓库不能直接调 Git Data API 建 blob**（409），得先用 Contents API 落一个文件。

## 常见问题

**Actions 里编译失败**
把报错日志发我，多数是 Swift 语法或工程配置问题，改 `ios/` 下的文件重推即可。

**装完打开是白屏**
说明本地服务或资源有问题。手机上开「设置 → 隐私与安全性 → 开发者模式」后再试；
还不行的话告诉我，我把 `WebViewController` 的兜底逻辑和日志再调一版。

**提示「无法验证 App」/ 闪退**
基本是签名没走完：证书没信任、或者开发者模式没开。

**换手机 / 想备份数据**
目前还没有导出功能。这条是已知最大风险，建议尽早加「导出 JSON」到「我」页。

---

## 已知没做的

- 休息结束的**本地通知**（现在靠网页内提示音，App 被系统彻底冻结时可能不响）
- Media Session（锁屏显示歌名、切歌）
- 数据导出备份
- 数据在网页版 / 安卓版 / iOS 版之间互通
