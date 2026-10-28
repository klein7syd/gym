REPS iOS 4.9.3（build 13）交付说明
======================================================================

一、安装包
----------------------------------------------------------------------
文件：REPS-4.9.3-unsigned.ipa
大小：927,947 字节
SHA256：40b58492fe435cb0fb327f36238570d128d1f25abd383bceb5410db7c5c84243
MD5：b770ed3699cb99431bd76dce53a449c4
直链（免登录）：
https://github.com/klein7syd/gym/releases/download/v4.9.3/REPS-4.9.3-unsigned.ipa

CI：GitHub Actions run 40655073713，一次通过（macos-latest / Xcode 26.6 / iOS SDK 26.5）
包内 Info.plist：CFBundleShortVersionString = 4.9.3，CFBundleVersion = 13，
DTSDKName = iphoneos26.5
包内二进制已确认含符号：DimOverlay / CardClip / NowPlayingView

签名照旧：包是**未签名**的，需用 Sideloadly 自行签名安装。


二、改了什么 / 为什么
----------------------------------------------------------------------

【1】根因：下拉手势用了 .local 坐标空间（抖动 / 闪烁的主因）

dismissDrag 挂在抓手、头部、封面、标题区上，而这几个视图都在**被 .offset(y: dragOffset)
移动的卡片内部**。

.local 是「视图自身坐标」。手指往下一动 → 卡片跟着下移 → 手指在这个局部坐标里的 y 被抵消
→ translation.height 变小 → dragOffset 变小 → 卡片弹回去 → 下一帧 translation 又变大……
形成正反馈回路，画面就是持续抖动 / 闪烁。

同时 player.pull = h / 260 也跟着来回跳，于是底下 TabView 的 scaleEffect、CardClip 半径、
DimOverlay 的压暗全部同步抖 —— 看起来就是「整个屏幕在闪」。

改法：DragGesture(minimumDistance: 8, coordinateSpace: .global)。
全局坐标不随卡片位移变化，拿到的才是手指真实位移，dragOffset 单调跟随。
阈值（110 / 260）、260pt 满进度、弹回 spring（0.34 / 0.86）一个都没改。


【2】拖动期间不再切换整个窗口的配色（第二处闪烁来源）

4.9.2 在拖动第一帧就 forceDark = false。整个窗口的 userInterfaceStyle 在拖动途中变化，
会触发全窗口重绘，叠在拖动每帧刷新上就是第二处闪烁。

现在：
  · 删掉 beginDismiss()、cancelDismiss()，以及 NowPlayingView 里的 dismissing 标记；
  · 拖动全程 forceDark 保持 true。底下露出的 TabView 是深色版 —— 这是可接受的，
    因为播放页和压暗层本身就是深色，视觉上连续，且全程没有一次跳变；
  · 弹回（没拖够）：什么都不做，配色一点不变，纯位置回弹；
  · 关闭（拖到底 / 点 ⌄）：**先**启动关闭动画，asyncAfter(0.30) 后再在回调里
    （复查 !isOpen）用 disablesAnimations 的 Transaction 无动画切回浅色。
    0.30s 时播放页已滑出大半、底层 TabView 已接近 scale 1，切换几乎不可见；
  · open() 未改：0.52s 后 forceDark = true，回调里复查 isOpen == true，
    防止 0.5s 内快速开→关时把窗口提前切成深色。


【3】封面去掉隐式动画

cover(side:) 上的 .animation(.easeOut(duration: 0.25), value: side) 已删除，没有用别的动画替代。
side 在拖动 / 安全区回退 / 布局重算时会变，那个 0.25s 动画让封面相对卡片滞后 0.25 秒，
拖动过程中就会出现「封面和卡片错位」的撕裂帧。


【4】压暗遮罩抽成独立小视图 DimOverlay

Color.black.opacity(0.42 * (1 - pull)) 从 RootTabView 的 overlay 里抽成 DimOverlay（只观察 player）。
数值与动画参数完全不变（0.42 / 0.46 spring / dampingFraction 0.90）。
DimOverlay 内部额外写了一遍同参数的 .animation(...value: player.isOpen)：因为它现在通过自己的
订阅收到 isOpen 变化，不保证落在根视图那圈 animation 事务里，少了它可能变成硬切；
参数与外层一模一样，视觉无差别。scaleEffect 与 CardClip 半径仍留在 RootTabView（按要求未动）。


三、文件变更清单
----------------------------------------------------------------------

新增文件：无
删除文件：无
Info.plist：未改动
依赖：未新增
未改动：CardClip（mask + ignoresSafeArea）、AppBackground、GlassBar、VolumeBar、
        MiniPlayerBar、QueueSheet、preferredColorScheme、所有既有数值

修改（4 个）：
  ios/REPS/MusicView.swift
      · dismissDrag：DragGesture 加 coordinateSpace: .global，删掉 beginDismiss 调用
      · 删除 @State dismissing
      · cover(side:)：删除 .animation(.easeOut(duration: 0.25), value: side)
  ios/REPS/PlayerChrome.swift
      · 删除 beginDismiss() / cancelDismiss()
      · close() 改为「先起关闭动画 → 0.30s 后复查 !isOpen 再切回浅色」
      · open() 未改（0.52s + isOpen 复查保持原样）
  ios/REPS/REPSApp.swift
      · overlay 里的 Color.black 换成 DimOverlay()
      · 文件末尾新增 private struct DimOverlay
  ios/project.yml
      · MARKETING_VERSION 4.9.2 → 4.9.3
      · CURRENT_PROJECT_VERSION 12 → 13


四、参数含义
----------------------------------------------------------------------

dismissDrag
  minimumDistance: 8   起拖阈值，小于 8pt 视为点按（保证 ⌄ / ⋯ 按钮可点），未改
  coordinateSpace       .global（本轮改动）：全局坐标，不随卡片 offset 变化
  h = max(0, dy)        只允许往下拉；往上推 h 恒为 0
  pull = min(1, h/260)  260pt 视为「拉到底」，下层缩放 / 压暗 / 圆角按这个比例插值
  far 判定              dy > 110 或 predicted > 260 就关闭
  弹回                  spring(response 0.34, dampingFraction 0.86)

close() / open()
  0.30s   关闭时延迟切回浅色的时刻（关闭 spring response 0.40，此时已滑出大半）
  0.52s   打开后切深色的时刻（打开 spring response 0.46，此时已盖满）
  两处回调分别复查 !isOpen / isOpen，保证 0.5s 内快速开关不会把状态切错
  Transaction.disablesAnimations = true：配色切换不走动画，
  避免 0.4s 渐变叠在手势上看更花

DimOverlay
  0.42 * (1 - pull)     压暗强度：完全打开 0.42，拉到底 0
  spring(0.46, 0.90)    与根视图那条完全一致

未改动的数值（保持原样）：34 / 20 / 0.94 / 0.06 / 0.42 / 260 / 110 / 0.5 / 0.13 /
                            340 / 0.82 / 24 / 462（播放页 fixed）


五、怎么测试
----------------------------------------------------------------------

① 慢速下拉到一半**不松手**，停住 3 秒
   预期：卡片稳稳停在那儿，不再来回抖；封面、歌名、进度条、音量条与卡片整体一起位移，
         没有封面比卡片慢半拍的感觉。
   ★ 这一条是本轮核心，务必看。

② 缓慢下拉一小段（不到一半）再松手
   预期：平滑弹回原位，全程颜色不变（不出现「先变浅又变深」）。

③ 下拉到底关闭
   预期：播放页往下滑出，滑到快没影时底下才由深转浅，全程没有一下明显的跳色。

④ 点左上角 ⌄ 按钮关闭
   预期：与 ③ 完全一致（走的是同一个 close()）。

⑤ 浅色系统模式 / 深色系统模式各把 ①~④ 做一遍
   预期：两种模式表现一致，深色模式下尤其注意有没有整屏闪白。

⑥ 打开播放页后 0.5 秒内立刻关闭，连做 5 次
   预期：状态栏文字颜色始终与当前页面匹配，不会出现「浅色页面上白字」或
         「深色播放页上黑字」；不会卡在某一色。

⑦ 顺带回归（本轮未改逻辑，但改了呈现生命周期，值得看一眼）：
   播放页里拖动进度条 / 音量条是否仍然跟手；播放列表拖动排序是否正常。


六、已知限制
----------------------------------------------------------------------

1. **未在真机验证。** 本机是 Windows，没有 Mac，也没有 iPhone。CI 只验证了：编译通过、
   包结构正确、版本号 4.9.3 / 13、二进制里含预期符号。抖动是否真的消失、配色切换是否真的
   看不见，**必须由你在手机上确认上面 ① ② ③ 三步**（⑥ 也建议做一遍）。

2. 拖动期间窗口一直是深色，所以下拉时露出的底层 TabView 是**深色版**。这是本轮刻意的取舍：
   换来的是全程零跳色。若希望下拉时底层是浅色版，就必须回到「拖动中切配色」，
   而那条路 4.9.2 已经证明会闪 —— 两者不能兼得。

3. DimOverlay 的抽取只是把遮罩这一段从根视图里拿出来。RootTabView 的 body 仍然读 pull
   （scaleEffect 和 CardClip 半径必须作用在 TabView 上，按要求留在原处），
   所以拖动时根视图**依旧每帧求值**。真正止抖的是第 1 条（坐标空间），不是第 4 条。
   彻底方案是把整个「卡片堆叠层」抽成只观察 pull 的子视图，本轮未做。

4. 拖动到一半时，播放页上下两条安全区会被 CardClip 的 mask 裁掉（仅拖动过程中，
   松手恢复）。这是 mask 方案的固有行为，本轮未改。

5. 整首播放依赖歌曲已在 Apple Music「资料库」中；系统音量仍只有 16 级（iOS 限制）。

6. GlassBar 的 DragGesture(minimumDistance: 0) 仍用 .local —— 已核查：它读的是
   v.location.x，所在视图不会被位移（拖动播放页时是整张卡片一起位移，局部 x 不变，
   且进度条自身的拖动不会移动卡片），保持不动。Components.swift 里 RepeatButton 的
   DragGesture 不使用 translation，同样不受影响。
