# REPS 3.0 — iOS 原生（SwiftUI · Liquid Glass）

纯 SwiftUI 实现，界面按新版 iOS 的液态玻璃语言重做：半透明材质、镜面高光描边、浮动阴影、彩色背景渗透。四个 Tab 常驻，切换不丢状态。

## 版本对比

| | 1.0 网页壳 | 2.0 原生 | 3.0 液态玻璃 |
|---|---|---|---|
| 界面 | HTML 仿 iOS | SwiftUI 原生控件 | **Liquid Glass 材质** |
| 底部栏 | 系统 TabView | 系统 TabView | **悬浮玻璃胶囊** |
| 音乐 | 仅本地 | 仅本地 | **+ Apple Music / 网易云** |
| 身体曲线 | 无 | 只有动作 1RM | **体重/体脂多指标双轴图** |
| 数据备份 | 无 | JSON | JSON |
| 息屏提醒 | 不会响 | 本地通知 | 本地通知 |

## 界面

**液态玻璃的做法**

系统的 Liquid Glass API 只在新版 SDK 上可用，这套实现用 Material + 自定义渐变描边模拟同样的观感，所以能装到 iOS 16 及以上：
- 材质：`.ultraThinMaterial` 打底
- 染色：左上白→右下暗的对角渐变，让背后色彩渗进来
- 高光：1pt 描边，左上亮、右下回光，模拟玻璃边缘折射
- 浮起：柔和外阴影 + 连续大圆角
- 背景：三团高斯模糊色斑，玻璃才有东西可透

**底部栏** 是悬浮胶囊，选中项有玻璃高光胶囊在四个位置间弹簧移动（matchedGeometryEffect），点击有轻微缩放和触感反馈。

## 四个 Tab

### 训练
- 动作卡片显示上次组数 / 最重 / 估算 1RM
- 重量 ±2.5 kg、次数 ±1，**按住连续变化**
- 完成一组自动起休息 + 触感反馈，可撤销上一组
- 109 个动作库：按肌群筛选，中英文/肌肉/器械搜索，自定义动作，每个带要领、常见错误、替代动作
- 结束保存 / 放弃本次

### 组间休息
- 玻璃圆环，60/90/120/180 秒，可 +30 秒、可跳过
- 用绝对时间戳算剩余，切后台不作废
- 前台铃声震动，**锁屏由系统通知提醒**

### 音乐
三段式：本地 / Apple Music / 网易云，Apple Music 风格布局（大封面、细线条、留白）。

- **本地**：从「文件」导入 mp3/m4a/wav，文件复制进沙盒永久保存；播放/暂停/上下首/拖进度；长按列表项可移除
- **Apple Music**：授权后可搜曲库，点结果唤起 Apple Music 播放。没有 `musickit` entitlement 时（免费签名就是这样）自动降级为跳转搜索页，不会卡住
- **网易云**：通过 `orpheus://` 唤起官方 App 并带上关键词，没装则回落网页版
- 本地播放支持锁屏与控制中心：歌名、切歌、拖进度

### 成长
- 本周总容量 / 本周训练次数 / 连续训练周数
- **身体数据曲线**：体重、体脂、去脂体重、FFMI 共用一张图
  - 横轴统一是「健身第几天」，从第一次训练算起
  - 每条曲线用各自的量程，左轴对应第一条、右轴对应第二条，量纲不同也能叠在一起
  - 点上方色块可增减指标
- 每个动作：1RM 趋势线、与上次差值、加重建议
- 历史训练可点开看每组明细，可删除

### 我的
- 基本信息（性别/身高/体重/年龄/体脂）
- 身体指标：BMI、理想体重区间、BMR、TDEE、去脂体重、FFMI、减到 15% 需减多少
- 围度估体脂（美国海军公式，女性需要臀围）
- 三大项 1RM → 相对体重倍率与等级
- 默认休息时长
- 导出 / 恢复 / 清空数据

**键盘问题已修**：体重身高这类数字输入现在有三种收键盘方式——向下滑动页面自动收、键盘上方「完成」按钮、导航栏「收起」按钮。

## 源码结构

```
ios/REPS/
  REPSApp.swift       入口 + 四 Tab 容器（页面常驻）
  Theme.swift         液态玻璃设计系统、背景、悬浮 TabBar、按钮样式
  Models.swift        数据模型（训练/档案/体重记录/音轨/动作库）
  Store.swift         数据层：持久化 + 全部计算
  RestTimer.swift     休息计时 + 本地通知
  AudioPlayer.swift   AVPlayer + 锁屏远程控制 + 文件导入
  MusicServices.swift Apple Music（MusicKit）与网易云接入
  Components.swift    长按连加、步进器、折线图、多指标双轴图、文件选择、分享
  TrainView.swift     训练页 + 动作库选择器 + 动作详情
  MusicView.swift     音乐页（Apple Music 风格）
  GrowthView.swift    成长页 + 曲线 + 训练详情
  ProfileView.swift   我的
  Resources/moves.json 109 个动作
```

约 3800 行 Swift，无第三方依赖，iOS 16.0+，仅竖屏。

## 编译

```bash
python tools/push-via-api.py "说明"   # 推代码，自动触发 Actions
python tools/download-ipa.py         # 拉最新 IPA 到 dist/
```

流水线 `.github/workflows/ios-ipa.yml`：macos-14 + XcodeGen，改 `ios/**` 或 `reps-data/**` 自动触发。

## 安装

1. 从 Release 下 IPA
2. Windows 用 [Sideloadly](https://sideloadly.io) 签名（iTunes 必须是官网版；双因素账号填专用密码）
3. 手机信任描述文件；iOS 16+ 还要在「隐私与安全性」里开开发者模式并重启

免费 Apple ID 签的包 7 天过期，重签即可。

## 注意

- **1.x 的数据不会自动迁移**（旧版在 WebView 的 localStorage）。
- **卸载会清空数据**。续期重签不要先卸载；换手机前先导出备份。
- 首次启动请允许**通知权限**，否则锁屏时休息结束不提醒。
- Apple Music 的完整曲库搜索需要付费开发者账号的 `musickit` entitlement，免费签名下会自动走跳转方案。
- 数据只存本机，无网络请求、无账号体系。

## 未验证

真机未跑过（开发环境只有 Windows）。产物经过 zip 完整性、Mach-O 架构、Info.plist、资源打包校验；界面观感、后台行为需要你在真机上确认。
