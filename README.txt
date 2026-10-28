REPS iOS 4.9.6（build 16）— 交付说明
================================================

安装包：REPS-4.9.6-unsigned.ipa（未签名，需自行用 Sideloadly 签名）
大小：976,092 字节
SHA-256：fc29f328847ab7d3e285792b4121557995b7568f45eee6137606e39d14e2e7bb
MD5：40ce565eaa09a736272a9094943775ad
直链：https://github.com/klein7syd/gym/releases/download/v4.9.6/REPS-4.9.6-unsigned.ipa
CI：run 40668854305（macos-latest / Xcode 26.6 / iOS SDK 26.5），一次通过
最低系统：iOS 16.0，仅 iPhone


一、改了什么 / 为什么
------------------------------------------------

上一轮的 B / C / D 三块当时没有落进代码（MusicView / PlayerChrome / REPSApp 未改），
本轮连同 A、E 一起做完，共五块。

A. 训练 / 组间歇 两阶段状态机
   以前「完成」和「跳过」两个按钮同时挂着，休息时长芯片还能随时重启倒计时，阶段是混的。
   现在改成严格两阶段：

     working --「完成这一组」--> 记录一组 + resting --归零 /「跳过休息」--> working → 下一组

   · 「完成」只在 working 出现，「跳过休息」只在 resting 出现；
   · working 阶段既没有「跳过」，也没有手动开始休息的时长按钮；
   · working 一律蓝（WorkStyle.ring = accentColor），resting 一律绿（RestStyle.ring）；
   · 训练页的倒计时圈改为常驻：working 显示蓝色「本组用时」递增，resting 显示绿色倒计时；
   · 三处「完成一组」（训练页 / 播放页训练卡 / 训练面板）都加了 guard !rest.isResting，
     休息中记不了组；
   · 训练页删掉了 60/90/120/180 预设芯片（点它们会重启休息，和新状态机冲突），
     时长只在 restSettingRow 的 Stepper 里改。

B. 下拉时的「灰带 + 黑圈」
   REPSApp 的根 ZStack 里，AppBackground 之上还叠了一层 Color(white: 0.13)（播放页深灰）
   当卡片堆叠的底。那层没有 ignoresSafeArea：页面缩小后四周露出一圈深灰，
   上下安全区又因为它是按安全区布局的而露出浅灰 —— 就是灰带 + 黑圈，
   与状态栏 / 电池区完全割裂。整层删除，底层只剩铺满安全区的 AppBackground。
   顺手删掉了它那条 .opacity / .animation(.easeInOut(duration: 0.25))。

C. 滑到底松手「跳一下」
   close() 原本第一行就 pull = 0，而 pull 同时驱动下层缩放和圆角。
   手势拉到底时 pull 约等于 1（下层几乎原样），一旦归零，下层立刻缩回最小尺寸 —— 视觉上跳一下。
   现在 close() 不再立刻清零：让 isOpen=false 的动画从当前 pull 继续插值，
   0.6s（spring response 0.40 已走完）后再复位；此时 isOpen 已是 false，
   CardClip 不生效、缩放也是 1，所以这次复位看不见。⌄ 按钮与手势走同一条 close()。

D. 搜索键盘叠在播放器上
   · PlayerPresenter.open() 开头 resignFirstResponder；
   · NowPlayingView.onAppear 再收一次，并整页加 .ignoresSafeArea(.keyboard, edges: .bottom)；
   · MusicView 与 AlbumDetailView 的 MiniPlayerBar 都加 .ignoresSafeArea(.keyboard, edges: .bottom)，
     键盘弹起时不再把迷你播放条顶到键盘上方；
   · 底层 TabView 在 .allowsHitTesting(!player.isOpen) 旁加了 .accessibilityHidden(player.isOpen)。
     没有用任务书里备选的 .disabled：.disabled 会把底下所有按钮画成灰态，
     而下拉过程中这层是看得见的，按钮会一个个变灰，副作用比收益明显。

E. 下拉缩放过大、内容挤成一坨
   缩放 0.94 + 0.06 * pull → 0.97 + 0.03 * pull（幅度 6% → 3%），
   圆角 34 - 20 * pull → 22 - 12 * pull，压暗 0.42 * (1 - pull) → 0.28 * (1 - pull)。
   只动这三个值，anchor / CardClip 结构 / 动画曲线都没碰。


二、文件变更清单
------------------------------------------------

修改（8 个，无新增、无删除、无新依赖、Info.plist 未改）

  ios/REPS/Theme.swift         新增 enum WorkStyle { static let ring = Color.accentColor }
  ios/REPS/RestTimer.swift     新增 workStart / beginWork() / isResting；skip()、finish() 末尾调用 beginWork()
  ios/REPS/Components.swift    RestRing 加 caption + color 参数；MiniRestRing 加 color 参数
  ios/REPS/TrainView.swift     restCard → 常驻 phaseCard（两阶段）；主按钮按阶段切换；
                               删预设芯片；completeSet 加守卫；onAppear 新 session 时 beginWork
  ios/REPS/MusicView.swift     trainingBar 改两阶段（圈常驻 + 按钮按阶段 + 文案）；
                               completeSet 加守卫；收键盘；两处 MiniPlayerBar 忽略键盘安全区
  ios/REPS/PlayerChrome.swift  TrainingSheet 加常驻 phaseCard（替代 restCard）+ 按阶段主按钮 + 守卫；
                               open() 收键盘；close() 不再先清 pull，0.6s 后复位
  ios/REPS/REPSApp.swift       删除 Color(white: 0.13) 那层；缩放/圆角/压暗三个数值；
                               TabView 加 accessibilityHidden
  ios/project.yml              4.9.5/15 → 4.9.6/16

被删除的文件：无


三、参数含义
------------------------------------------------

WorkStyle.ring = Color.accentColor
    训练阶段（working）的颜色。蓝 = 我在练。

RestStyle.ring = Color.green
    组间歇（resting）的颜色。绿 = 我在歇。只用于休息圈、休息按钮、休息图标。

RestTimer.workStart
    当前这一组的开始时刻，纯内存态、不落盘。App 重启后从启动时刻算。

RestTimer.beginWork()
    把本组计时归零（workStart = now，同时刷新 tick）。
    调用点：skip() 末尾、finish() 末尾、TrainView 新 session、三处 completeSet 新建 session 时。

RestTimer.isResting == isRunning
    working = !isResting。全工程不再直接用 isRunning 判断阶段。

本组用时进度
    elapsed = now - workStart；progress = elapsed.truncatingRemainder(dividingBy: 60) / 60
    每满 60s 走完一圈，数字继续递增（1:23 → 2:05 …）。
    由 TimelineView(.periodic(from: .now, by: 1)) 驱动，不新开 Timer。

主按钮与阶段（对照表）

  阶段      训练页主按钮              播放页训练卡右侧        训练面板主按钮
  --------  ------------------------  ----------------------  ------------------------
  working   蓝「完成这一组」          只有蓝「完成」          蓝「完成一组」
  resting   绿「跳过休息」            「+30」+ 绿「跳过」     绿「跳过休息」+ 卡内「+30」
  阶段卡内  绿圈 +「+30 秒 / 跳过休息」  ——                    绿圈 +「+30 / 跳过」

fixed = 462（播放页除封面外的固定高度）
    本轮没有改。训练卡按钮列从最多三个（31×3 + 18 = 111pt）降到最多两个（31×2 + 9 = 71pt），
    圈一直是 62pt，文字列约 70pt，都没有超过原来的最高一档，所以预算不变。

缩放 0.97 + 0.03 * pull
    下层页面在播放页打开时缩到 97%，下拉到一半最深时回到 100%。幅度 3%。

圆角 22 - 12 * pull
    下层卡片圆角，播放页打开时 22pt，下拉越深越小，拉到底为 10pt。

压暗 0.28 * (1 - pull)
    下层压暗峰值从 0.42 降到 0.28。

0.6s
    close() 里复位 pull 的延迟，略大于关闭 spring（response 0.40）。


四、怎么测试
------------------------------------------------

① 训练页：完成一组 → 看绿圈倒计时 → 点「+30 秒」→ 点「跳过休息」→ 看蓝圈从 0:00 重新计时；
   再做一组，这次让它自然归零（把休息时长调到 15s 最快），确认归零后也回到蓝圈、有触觉反馈。
② 播放页训练卡与训练面板重复 ①：打开播放页 → 底部训练卡点「完成」→ 绿圈出现，
   和训练页读秒一致 → 直接切到训练 tab 看是否同一状态；再点开训练面板看是否同步。
③ 休息中确认无法记组：绿圈倒计时期间，训练页主按钮是「跳过休息」而不是「完成这一组」，
   播放页训练卡右侧没有「完成」。
④ 播放页慢速下拉：看四周有没有黑圈 / 灰带，看页面缩小的幅度是否轻微（不应挤成一坨）。
⑤ 下拉到底松手 / 点左上角 ⌄ 关闭：看底下页面是否连续放大，不再「跳一下」。
⑥ 音乐页点搜索框弹出键盘 → 点迷你播放条：播放页打开时键盘应已收起；
   播放页开着时点不到底下的搜索框。
⑦ 深色系统模式下把 ④⑤ 重做一遍。


五、已知限制
------------------------------------------------

1. 未在真机验证。CI 只验证了编译通过、包结构、版本号 4.9.6/16、关键符号；
   所有视觉与手势表现都需要你上机确认，重点是 ① ④ ⑤ ⑥。

2. 「本组用时」不落盘：workStart 只在内存里，App 被系统杀掉重开后从启动时刻起算，
   中场休息期间的本组用时不会保留（符合任务书「不新增持久化」）。

3. RestRing 多了一个 caption 参数（默认「休息中」）。任务书只要求加 color，
   但 working 阶段如果沿用写死的文案，圈里会显示「休息中」——所以第二行小字也做成了参数。

4. 训练页 restSettingRow 的图标保持绿色（休息标识），右侧「120s」数字改成 .primary：
   训练页除休息圈 / 休息按钮 / 休息图标外不再有绿色。

5. 我的页「训练设置」里原有的 4 个休息时长预设仍保留（本轮未动），
   与训练页 Stepper 写的是同一个 store.restSeconds，两边互相同步。

6. 整首播放仍要求歌曲已在 Apple Music「资料库」；系统音量仍只有 16 级。

7. 下拉压暗与缩放都调小了，播放页边缘的对比会比以前弱一点 —— 这是「不再挤成一坨」的代价。
