REPS iOS 4.9.4（build 14）交付说明
======================================================================

一、安装包
----------------------------------------------------------------------
文件：REPS-4.9.4-unsigned.ipa
大小：930,201 字节
SHA256：d5b183b960d8d29a8d9f9381447a211e8a1a5585f7bfcec5ba30d381c1fe55df
MD5：da53eb791f1353ca02808880c9e1f677
直链（免登录）：
https://github.com/klein7syd/gym/releases/download/v4.9.4/REPS-4.9.4-unsigned.ipa

CI：GitHub Actions run 40656526040，一次通过（macos-latest / Xcode 26.6 / iOS SDK 26.5）
包内 Info.plist：CFBundleShortVersionString = 4.9.4，CFBundleVersion = 14，
DTSDKName = iphoneos26.5
包内二进制已确认含符号：beginDismiss / cancelDismiss / isDragging / DimOverlay / CardClip
（setDragging 是极小的内部函数，Release 编译时被内联，查不到符号名属正常）

签名照旧：包是**未签名**的，需用 Sideloadly 自行签名安装。


二、改了什么 / 为什么
----------------------------------------------------------------------

【根因】

下拉期间底下露出来的 TabView 是哪一版配色，完全取决于 PlayerPresenter.forceDark。

4.9.3 为了消除闪烁，让拖动全程 forceDark = true。结果：
  · 下拉时露出的是**深色版**页面；
  · 关闭时才（0.30s 回调里）切回浅色 → 那一整页当场由深变亮 = 你看到的「深色/亮色跳变」。

4.9.2 的思路其实是对的：下拉露出来的页面应当**一开始就是最终那一版浅色**，
所以切色必须发生在「拖动刚开始、位移还只有几 pt、底下几乎没露出」的那一帧。

当时之所以会闪，根因是 DragGesture 的 .local 坐标空间（4.9.3 已用 .global 修掉），
和配色切换这件事无关。两件事必须分开看。

【1】恢复 beginDismiss()

    func beginDismiss() {
        guard forceDark else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { forceDark = false }
    }

无动画切换 —— 带动画会变成 0.4s 渐变，叠在手势上更花。

【2】新增 isDragging（普通属性，不是 @Published）

    private(set) var isDragging = false
    func setDragging(_ v: Bool) { isDragging = v }

只给 cancelDismiss 的延迟回调做守卫用，不需要触发任何视图刷新，所以刻意不加 @Published。

【3】恢复 cancelDismiss()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
        guard self.isOpen, self.pull == 0, !self.isDragging else { return }
        self.forceDark = true
    }

0.36s 略大于弹回 spring 的 0.34s，等卡片回到原位、重新盖满屏之后才切深色，看不见。
!isDragging 防止：用户在 0.36s 内又开始拖，结果被回调拉回深色。

【4】close() 恢复 4.9.2 逻辑

    guard isOpen else { return }
    pull = 0
    if forceDark {
        无动画 forceDark = false
        asyncAfter(0.05) { withAnimation(spring 0.40 / 0.92) { isOpen = false } }
    } else {
        withAnimation(spring 0.40 / 0.92) { isOpen = false }
    }

先切浅色、让配色单独渲染一帧，0.05s 后再启动下滑 —— 播放页滑出的整个过程里，
底下露出来的都是已经切好的浅色页面。
**4.9.3 里「0.30s 后才 forceDark = false」的整段回调已删除**，它就是跳变来源。

【5】⌄ 按钮关闭同样走 close()，行为完全一致。

【6】open() 保持 0.52s 后 forceDark = true，回调里查 isOpen；
    额外加了一个 !isDragging 守卫，见下面第六节「本版偏离说明」。

【7】dismissDrag（MusicView）

onChanged：
    let h = max(0, v.translation.height)
    if h > 0 && !dismissing { dismissing = true; player.setDragging(true); player.beginDismiss() }
    dragOffset = h
    player.pull = min(1, h / 260)

onEnded：
    dismissing = false; player.setDragging(false)
    far → player.close()
    否则 withAnimation(spring 0.34 / 0.86) { dragOffset = 0; player.pull = 0 }
         然后 player.cancelDismiss()

【8】核查项（均通过，未改动）
  · DragGesture(minimumDistance: 8, coordinateSpace: .global) —— 已是 .global
  · cover(side:) 上没有 .animation(.easeOut(duration: 0.25), value: side) —— 已删除，没回退


三、文件变更清单
----------------------------------------------------------------------

新增文件：无
删除文件：无
Info.plist：未改动
依赖：未新增
未改动：CardClip（mask + ignoresSafeArea）、DimOverlay、AppBackground、GlassBar、VolumeBar、
        MiniPlayerBar、QueueSheet、preferredColorScheme、REPSApp.swift（本轮未改）、
        所有既有数值（34 / 20 / 0.94 / 0.06 / 0.42 / 260 / 110 / 0.5 / 0.13 / 340 / 0.82 / 24 / 462）

修改（3 个）：
  ios/REPS/PlayerChrome.swift
      · 恢复 beginDismiss()
      · 新增 isDragging + setDragging(_:)
      · 恢复 cancelDismiss()（含 !isDragging 守卫）
      · close() 恢复「先切浅色 → 0.05s 后下滑」，删除 0.30s 回调
      · open() 的 0.52s 回调增加 !isDragging 守卫
  ios/REPS/MusicView.swift
      · 新增 @State dismissing
      · dismissDrag.onChanged：首帧 setDragging(true) + beginDismiss()
      · dismissDrag.onEnded：setDragging(false)，弹回分支调用 cancelDismiss()
  ios/project.yml
      · MARKETING_VERSION 4.9.3 → 4.9.4
      · CURRENT_PROJECT_VERSION 13 → 14

REPSApp.swift 本轮**未改动**（任务书第三节要求核查，层级与数值都已确认无需改）。


四、参数含义
----------------------------------------------------------------------

beginDismiss()     拖动第一帧调用；仅当 forceDark == true 时无动画置 false
isDragging         普通属性（非 @Published），标记「手指是否按下并拖动中」
setDragging(_:)    唯一写入点：onChanged 首帧置 true，onEnded 置 false
cancelDismiss()    弹回时调用；延迟 0.36s，复查 isOpen && pull == 0 && !isDragging
0.36s              弹回 spring 是 response 0.34，取 0.36 保证动画已结束
close()
  0.05s            先切浅色后等一帧（约 3 帧 @60Hz）再启动下滑动画
  spring 0.40 / 0.92   关闭动画，未改
open()
  0.52s            打开 spring 是 response 0.46，取 0.52 保证已盖满屏
  spring 0.46 / 0.90   打开动画，未改
dismissDrag
  minimumDistance 8  起拖阈值，保证 ⌄ / ⋯ 按钮可点
  coordinateSpace    .global（4.9.3 起）
  h = max(0, dy)     只允许往下拉
  pull = min(1, h/260)   260pt 视为拉到底，控制下层 scale / 压暗 / 圆角
  far 判定           dy > 110 或 predicted > 260
  弹回               spring 0.34 / 0.86

配色与下层（本轮未改，仅核查）：
  forceDark = false  → preferredColorScheme 传 nil，跟随系统
  底层 AppBackground() → Color(white: 0.13)（opacity 随 isOpen）→ TabView
  压暗 0.42 * (1 - pull)


五、怎么测试
----------------------------------------------------------------------

① 浅色系统模式：缓慢下拉到一半**不松手**，停住 3 秒
   预期：底下露出来的那半屏页面**始终是浅色**，从第一 pt 到停住那一刻都不变色；
         同时卡片不抖（.global 未回退）。

② 松手弹回 → 再下拉到底关闭
   预期：弹回全程浅色不变；关闭时播放页往下滑出，底下自始至终是浅色页面，
         不会出现「滑到一半底下突然由深变亮」。

③ 点左上角 ⌄ 按钮关闭
   预期：与 ② 一致，全程浅色，无跳变。

④ 深色系统模式把 ①~③ 各做一遍
   预期：一样无跳变。forceDark = false 时状态栏跟随系统（深色），不存在浅/深打架。

⑤ 打开后 0.5s 内立刻关闭，连做 5 次
   预期：状态栏文字颜色始终与当前页面匹配，不会卡在某一色，也不会出现整屏闪白。

⑥ 顺带回归：播放页里拖进度条 / 音量条是否跟手；播放列表拖动排序是否正常。


六、已知限制
----------------------------------------------------------------------

1. **未在真机验证。** 本机 Windows，无 Mac、无 iPhone。CI 只验证了编译通过、包结构、
   版本号 4.9.4 / 14、二进制含预期符号。颜色跳变是否真的消失**必须由你在手机上确认
   ①②③ 三步**。

2. **状态栏会瞬间闪一下（预期行为，不是 bug）。**
   下拉最初那几 pt —— 也就是切配色的那一帧 —— 状态栏文字会由白变黑，短暂压在深色播放页上。
   这是「把切色提前到几乎看不见位移的那一帧」的必然代价。要彻底消除它，只能改成给状态栏单独
   指定颜色（改 navigationBar / statusBar 的外观策略），那条路风险更大，本版不走。

3. **本版有一处偏离任务书**：open() 的 0.52s 回调里，除了 `isOpen` 还多了 `!isDragging`。
   原因：若用户在打开后约 0.3s 就开始下拉（播放页还在滑入、forceDark 仍为 false），
   0.52s 回调会把窗口切成深色 —— 又是在拖动中途翻色，等于没修好。
   加上守卫后这种情况保持浅色，由 cancelDismiss 的 0.36s 回调兜底恢复深色。
   除这一个条件外，open() 与任务书完全一致。

4. RootTabView 的 body 仍然读 pull（scaleEffect / CardClip 半径必须作用在 TabView 上），
   所以拖动时根视图依旧每帧求值。这是性能层面的遗留，不影响本版要修的颜色跳变。

5. 拖动到一半时，播放页上下两条安全区会被 CardClip 的 mask 裁掉（仅拖动过程，松手恢复）。

6. 整首播放依赖歌曲已在 Apple Music「资料库」中；系统音量仍只有 16 级（iOS 限制）。

7. GlassBar 的 DragGesture(minimumDistance: 0) 仍用 .local —— 已核查：它读的是 v.location.x，
   所在视图不会被位移（拖动播放页时整张卡片一起位移，局部 x 不变；进度条自身拖动不会移动卡片），
   保持不动。Components.swift 里 RepeatButton 的 DragGesture 不使用 translation，同样不受影响。
