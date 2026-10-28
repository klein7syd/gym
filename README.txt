REPS iOS 4.9.5（build 15）交付说明
======================================================================

一、安装包
----------------------------------------------------------------------
文件：REPS-4.9.5-unsigned.ipa
大小：947,875 字节
SHA256：8d4b19931b876814c998b7d70280dd48e60d2be45d02e377aa4e86b32ede8028
MD5：98e87f72a85802e59ae14fe3f85f7703
直链（免登录）：
https://github.com/klein7syd/gym/releases/download/v4.9.5/REPS-4.9.5-unsigned.ipa

CI：GitHub Actions run 40660672175，一次通过（macos-latest / Xcode 26.6 / iOS SDK 26.5）
包内 Info.plist：4.9.5 / build 15，DTSDKName = iphoneos26.5
包内二进制已确认含符号：RestStyle / RestRing / MiniRestRing / RestSettingSheet

签名照旧：包是**未签名**的，需用 Sideloadly 自行签名安装。


二、第 0 步：现状核查（a–d 的答案）
----------------------------------------------------------------------

a. 训练主页那个「随倒计时走的圆圈」由什么驱动？
   已经是 rest.progress —— `TrainView.restCard` 里的 `RestRing(progress: rest.progress,
   text: rest.remainingText)`，而整个 restCard 包在 `if rest.isRunning { … }` 里。
   不是训练计时、也不是目标时间。→ 属于**情形 A**，本轮只改颜色，不新增/覆盖任何圈。

b. 三处「完成一组」是否都会 rest.start(seconds: store.restSeconds)？
   是，三处都齐：
     · TrainView.completeSet()（训练页「完成一组」）
     · NowPlayingView.completeSet()（播放页训练卡的「完成」）
     · TrainingSheet.completeSet()（训练面板的「完成一组」）
   三者都是「ensureSession → logSet → 触觉反馈 → rest.start(seconds: store.restSeconds)」。

c. 休息结束的提醒 / 后台 / 回前台重算：
   · 触觉：有（finish() 里 UINotificationFeedbackGenerator().notificationOccurred(.success)，
     并叠加 SystemSound 1005 + kSystemSoundID_Vibrate）；
   · 本地通知：有（RestTimer.scheduleNotification 用 UNTimeIntervalNotificationTrigger，
     identifier = "reps.rest.finished"；REPSApp.init 里已请求授权）；
   · 回前台：有（remaining 一直按 endDate − tick 计算，tick 由 0.2s Timer 和
     willEnterForegroundNotification 刷新；回前台若已过期直接 finish()）。
   本轮只补一处：finish() 里加 cancelNotification()，避免「前台已判定归零、通知才触发」
   导致稍后再弹一条重复提醒。

d. store.restSeconds 在哪可以改？
   两处已存在：
     · 我的页 → 训练设置：60 / 90 / 120 / 180 四个预设；
     · 训练页休息卡里：同样四个预设芯片（休息中可见）。
   但都只有固定预设、且训练页那排只在休息中才出现。本轮**新增**训练页常驻入口 +
   15–600s、步长 15 的 Stepper（见下）。


三、改了什么 / 为什么
----------------------------------------------------------------------

【1】颜色：休息绿、训练蓝

Theme.swift 新增：

    enum RestStyle {
        static let ring = Color.green
    }

- RestRing（训练页组间歇倒计时）进度弧：Color.accentColor → RestStyle.ring
- MiniRestRing（播放页训练卡 / TrainingSheet）进度弧：Color.accentColor → RestStyle.ring
- 底环（Color(UIColor.tertiarySystemFill)）不动；尺寸、线宽（12 / size*0.09）、
  0.2s linear 动画全不动
- 两个环中间的倒计时文字本来就是 .primary，不是 accentColor，按规则**未改**
- 训练页的预设芯片、按钮、选中胶囊等 accentColor 一律未动（训练本身仍是蓝色）

【2】训练页新增休息时长入口（Stepper）

- 在 exerciseCard 下方加一行常驻卡片：`⏱ 组间休息 ——— 120s ›`，数字用 RestStyle.ring 绿色；
  点整行弹出 RestSettingSheet。
- RestSettingSheet：
    · 大号绿色数字显示当前值；
    · Stepper(value: $value, in: 15...600, step: 15)；
    · 45 / 60 / 90 / 120 / 180 快捷芯片；
    · 每次改动立刻 store.restSeconds = value（Store 内部 clamp 15…600 并 save()）。
- 不新增任何存储字段：restSeconds 本来就在 PersistedState 里，旧存档解码缺字段默认 120
  （Models.swift 里 (try? c.decode(Int.self, forKey: .restSeconds)) ?? 120），完全向后兼容。
- 这行在休息中也可见，正好贴在绿色倒计时圈的正上方。

【3】RestTimer.finish() 取消排队通知

    private func finish() {
        cancelNotification()   // ← 本轮新增这一行
        endDate = nil
        …
    }

理由：前台 tick 可能比通知触发早几十毫秒判定归零，不取消的话稍后一进后台会再弹一条。

【已有，未重写】功能清单里的 1 / 2 / 4 / 5 / 6 都已经实现，只在第 4 项补了上面那一行。
【功能对照表】

  功能                                 状态    位置
  ----------------------------------  ------  --------------------------------------------
  1 完成一组 → 记组 + 立刻开始休息      已有    三处 completeSet
  2 倒计时中 +30 / 跳过（三处一致）     已有    三处休息卡/训练卡
  3 休息时长可调（15–600，步长 15）     新增    TrainView.restSettingRow + RestSettingSheet
  4 结束触觉 + 后台本地通知             已有    RestTimer.finish / scheduleNotification
    4' finish 时取消排队通知            新增    RestTimer.finish 第一行
  5 剩余时间按 endDate − now            已有    RestTimer.remaining
  6 休息中再次完成一组不叠加            已有    start() 内重建 endDate + 先取消通知 + ticker 先停


四、文件变更清单
----------------------------------------------------------------------

新增文件：无
删除文件：无
Info.plist：未改动
依赖：未新增
存储结构：未改动（restSeconds 复用 PersistedState 既有字段）
未改动：MusicView.swift、PlayerChrome.swift、REPSApp.swift、Store.swift、Models.swift、
        以及所有既有尺寸 / 线宽 / 动画参数

修改（5 个）：
  ios/REPS/Theme.swift
      · 新增 enum RestStyle { static let ring = Color.green }
  ios/REPS/Components.swift
      · RestRing 进度弧 → RestStyle.ring
      · MiniRestRing 进度弧 → RestStyle.ring
  ios/REPS/TrainView.swift
      · @State showRestSetting
      · VStack 中 exerciseCard 之后插入 restSettingRow
      · .sheet 挂 RestSettingSheet
      · 新增 restSettingRow 视图
      · 文件末尾新增 struct RestSettingSheet
  ios/REPS/RestTimer.swift
      · finish() 首行加 cancelNotification()
  ios/project.yml
      · MARKETING_VERSION 4.9.4 → 4.9.5，CURRENT_PROJECT_VERSION 14 → 15


五、参数含义
----------------------------------------------------------------------

RestStyle.ring       组间歇专用绿；只用于两个休息环的进度弧
Stepper 范围          15...600（秒），步长 15
store.restSeconds     get 直读 state；set 时 clamp 到 15…600 并 save()（Store.swift）
默认值                120（PersistedState 默认值 + 解码兜底，旧存档安全）
rest.progress         1 − remaining/total，remaining = max(0, ceil(endDate − tick))
rest.progress 动画    .linear(duration: 0.2)，未改
RestRing 线宽         12；MiniRestRing 线宽 size * 0.09（62 / 58 两处调用），未改
RestTimer tick        0.2s（RunLoop .common），另有 willEnterForeground 时刷新并补判过期
finish()              cancelNotification → endDate=nil → 停 ticker → 恢复 idleTimer →
                      系统音 1005 + 震动 + .success 触觉
通知 identifier       "reps.rest.finished"（start / skip / finish 都会取消它）


六、怎么测试
----------------------------------------------------------------------

① 训练页点「完成一组」
   预期：组被记录；页面出现**绿色**倒计时圈（底环灰色不变），数字逐秒递减。

② 休息中点「+30 秒」→ 再点「跳过」
   预期：+30 让剩余时间加 30 秒且圈不重置；跳过立刻收起休息卡、恢复常态（蓝色界面）。

③ 再点一次「完成一组」
   预期：重新开始一轮倒计时（不会出现两个计时器、数字不会双倍速跳）。

④ 改休息时长
   点训练页「组间休息 120s ›」→ Stepper 调到 60 → 完成 → 点「完成一组」
   预期：按 60s 倒计时；杀掉 App 重开，入口处仍显示 60s。

⑤ 播放页训练卡 / 训练面板的休息圈
   预期：同样是绿色，且与训练页是同一个计时器（三处数字同步）。

⑥ 锁屏 / 切后台
   开始休息 → 锁屏 30 秒 → 回来：剩余时间正确（按结束时间戳算，不是累减）。
   再试：开始休息 → 立刻切后台 → 等到点：收到「休息结束」本地通知。
   再试：开始休息 → 点「跳过」→ 切后台：**不应**再收到通知。

⑦ 训练页完成一组 → 看绿圈 → +30 → 跳过 → 再完成一组（完整跑一遍上表 1/2/6）

⑧ 改休息时长为 60s，完成一组验证（对应上表 3）

⑨ 开始休息后锁屏 30 秒再回来，以及切后台等到通知（对应上表 5 / 4）

⑩ 回归：训练本身的蓝色（完成一组按钮、选中胶囊、勾选图标）是否仍为蓝色，没被染绿。


七、已知限制
----------------------------------------------------------------------

1. **未在真机验证。** 本机 Windows，无 Mac、无 iPhone。CI 只验证了编译通过、包结构、
   版本号 4.9.5 / 15、二进制含预期符号。请重点确认 ①②④⑤⑥。

2. 训练页原有四个预设芯片（60/90/120/180）与新的 Stepper 并存。
   用 Stepper 设成非预设值（如 45s、150s）时，那排芯片都不高亮 —— 功能正常，只是没有选中态。

3. 播放页训练卡里那个「\(restSeconds)s」小按钮仍然是「点一下立刻按这个时长开始休息」，
   不是设置入口；设置入口只放在训练页（按任务书要求）。

4. 倒计时圆圈是「进度弧从空长到满」（progress = 1 − remaining/total），
   不是从满缩到空。这是原有表现，本轮按「已有的不要重写」未改。

5. 本地通知在 App 处于前台时不会弹横幅（没有设置 UNUserNotificationCenter delegate），
   前台靠系统音 + 震动 + 触觉反馈提醒 —— 这是原有行为。

6. 系统音量仍 16 级、整首播放依赖资料库等既有音乐侧限制与本轮无关，未改动。
