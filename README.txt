REPS iOS 4.9.1（build 11）交付说明
======================================================================

一、安装包
----------------------------------------------------------------------
文件        REPS-4.9.1-unsigned.ipa
大小        917,436 字节（0.87 MB）
SHA-256     a5e8c709d000453d7f69b6dbf4e041bd632228a7d99d009441c24cd02408a490
MD5         e9a163c43ee0510aa5307bc956504fb8
直链        https://github.com/klein7syd/gym/releases/download/v4.9.1/REPS-4.9.1-unsigned.ipa
Release     https://github.com/klein7syd/gym/releases/tag/v4.9.1
构建        GitHub Actions run 40648131144（macos-latest，Xcode 26.6，iOS SDK 26.5）
版本        4.9.1 / build 11（4.9.0 是 build 10）
签名        未签名。Sideloadly 自签：Apple 官网版 iTunes + Apple ID，双重认证填专用密码；
            装完到 设置 → 通用 → VPN与设备管理 信任证书，iOS 16+ 还要开开发者模式。
            免费账号 7 天过期；重签时别先卸载 App，否则沙盒里的训练记录会一起没。

交付物三件：本文件（README.txt）、CodeReview.txt（本轮改动文件的完整代码）、
上面的 IPA。


二、改了什么 / 为什么
----------------------------------------------------------------------
1）CardClip 不再用 if/else 切分支（本版主修）
   4.9.0 的实现是：
       @ViewBuilder body { if active && radius > 0.01 { 裁 } else { 原样 } }
   if/else 在 SwiftUI 里是 _ConditionalContent —— 两个分支是不同的结构身份。
   active 一翻转，SwiftUI 会把 content 整个销毁重建。对根 TabView 来说，打开/关闭
   播放页时就会丢：选中的 tab、各页 ScrollView 的滚动位置、NavigationStack 的路径；
   过渡也会退化成淡入淡出，不是连续插值。
   现在 body 永远返回同一种结构，只有 effectiveRadius 这个数值在变：
       content.mask { RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                            .ignoresSafeArea() }
       effectiveRadius = (active && radius > 0.01) ? radius : 0
   结构身份不变 → 状态不丢；数值变化能被外层
   .animation(.spring(response: 0.46, dampingFraction: 0.90), value: player.isOpen) 连续驱动。

2）为什么是 mask，不是 clipShape（黑边修复不能回退）
   clipShape 的裁剪边是**视图的布局 frame**，而 TabView / 页面是按安全区布局的，
   所以圆角为 0 也会沿安全区矩形硬切，把铺到状态栏、底部横条上的部分削平 → 黑边。
   mask 里的形状带了 .ignoresSafeArea()，圆角为 0 时是一块**覆盖整屏（含两条安全区）的矩形**，
   不切边；需要圆角时半径变大，遮罩变成圆角矩形，一切仍在整屏范围内。

3）播放页修饰符顺序改成「背景 → CardClip → offset」
   遮罩要盖在卡片本身上，再让整张卡片往下位移，圆角才会跟着卡片走；
   原来是先 offset 再 mask，遮罩会留在原地（虽然之前是 clipShape，但顺序同样要改）。

4）SafeArea.insets 兜底改严
   · 场景选择：优先 activationState == .foregroundActive，回退第一个场景；
   · 窗口：优先 keyWindow，回退 windows.first；
   · 取不到窗口、或首帧 top 还是 0（还没布局）时，回退 top 59 / bottom 34（灵动岛基准），
     原来是 47，而且窗口存在但安全区还没算好时会返回 0，播放页内容就会顶到状态栏下面。
   检查结论：原实现没有选前台场景、兜底是 47、且可能返回 0 —— 属于需要改，已改。
   布局常量 fixed = 448、side 上限 340、宽比 0.82、inset = 24 一个都没动。

5）本地曲目「正在播放」高亮改成按 id 比较
   PlayItem 对本地曲目本来就是 id = Track.id.uuidString（MusicHub.localItems），
   所以不用改模型：hub.current?.id == track.id.uuidString。同名歌不会再一起高亮。
   （顺带确认：本地列表的 index 用的是 filter 前的 offset，playLocal(at:) 也是按
   未过滤队列取，两者一致，不存在点错歌的问题。）—— 只改了高亮，没动别的。

6）底层色淡入
   Color(white: 0.13) 的 opacity 加了 .animation(.easeInOut(duration: 0.25), value: player.isOpen)，
   和 TabView 的 spring 时长大致匹配，避免 forceDark 已切深色而这一层还是浅灰时硬闪一帧。
   preferredColorScheme 没有移除（改状态栏文字颜色的方案风险大，本版不动）。

7）版本号 4.9.0（10）→ 4.9.1（11）。


三、文件变更清单
----------------------------------------------------------------------
新增       无
修改       ios/REPS/Theme.swift        CardClip 改 mask + 结构恒定（去掉 if/else、去掉 @ViewBuilder）
           ios/REPS/PlayerChrome.swift SafeArea.insets 场景/窗口选择与 59/34 兜底
           ios/REPS/MusicView.swift    播放页顺序改「背景→CardClip→offset」；本地高亮按 id
           ios/REPS/REPSApp.swift      底层色 opacity 加 0.25s easeInOut
           ios/project.yml             版本号 4.9.1 / build 11
删除       无
新增依赖   无；Info.plist 未改；AppBackground / GlassBar / VolumeBar / MiniPlayerBar /
           QueueSheet 均未动


四、参数含义
----------------------------------------------------------------------
CardClip(active:radius:)
            active = false，或 radius <= 0.01 时，effectiveRadius = 0，
            遮罩是「覆盖整屏的矩形」——视觉上等于不裁，但结构还在（不重建视图）。
            签名保持 CardClip(active: Bool, radius: CGFloat)，两个调用点没变。

34 - 20 * player.pull
            底层卡片圆角：播放页全开 34pt，下拉满（pull = 1）收到 14pt。
0.94 + 0.06 * player.pull
            底层卡片缩放：打开 0.94，拉回 1.00。
0.42 * (1 - pull)
            底层压暗程度，跟着下拉变亮。
dragOffset > 0.5         播放页拖动阈值（0.5pt 内视为没拖，圆角按 0 处理）。
min(34, dragOffset / 5)  播放页拖动圆角：位移 170pt 时到顶 34pt。
Color(white: 0.13)       播放页底色 / 卡片堆叠的底 = #212121。
easeInOut(0.25)          底层色淡入时长，配合 TabView 的 spring。
SafeArea fallback 59/34  取不到窗口时的安全区（灵动岛机型）。
fixed = 448              播放页除封面外的固定高度（本版未动）。
side ≤ 340、宽比 0.82    封面尺寸规则（本版未动）。
MARKETING_VERSION / CURRENT_PROJECT_VERSION = 4.9.1 / 11


五、怎么测试
----------------------------------------------------------------------
1. 冷启动 App：训练页看状态栏与底部标签栏是否都铺满，上下无黑条；
   音乐 / 成长 / 我的 三页各点一遍。
2. 进播放页：**还没拖动时**就应铺满整屏（状态栏区域是灰玻璃，不是黑的），
   底部横条区域也是玻璃。
3. 播放页往下拖再松手关闭：拖动时圆角出现并跟着卡片移动（不是钉在屏幕角落），
   松手滑出；连续开关 3 次，确认没有残留黑边。
4. 状态保持（本版重点，新增）：
   音乐页滚到一半 → 点进某张专辑详情 → 打开播放页 → 再关闭 →
   回来后滚动位置和导航栈必须还在；连开连关 3 次，选中的 tab 不应跳回训练页。
5. 深色模式冷启动（新增）：设置 → 显示与亮度 → 深色，杀掉 App 重开，
   底层颜色与页面一致，无黑条、无闪烁；再进出一次播放页看有没有闪。
6. 本地音乐：导入两首同名歌（可复制同一个 m4a 改名），播放其中一首，
   只有那一行高亮，另一行不高亮。
7. 回归：专辑网格 → 专辑详情 → 播放；训练页记一组、休息计时；音量条 / 进度条拖动。


六、已知限制
----------------------------------------------------------------------
· 未在真机验证（本机 Windows，CI 只验证了编译通过、包结构、Info.plist 版本号 4.9.1/11）。
  mask + ignoresSafeArea 的实际渲染效果必须由你在手机上确认第 1、2、3 步
  ——尤其第 2 步（静止无黑边）和第 1 步（整屏铺满），这两处是本次改动的核心。
· 关闭播放页时 forceDark = false 早于关闭动画开始（PlayerPresenter.close()）：
  窗口会在播放页仍然盖满屏幕的那 0.4 秒里切回浅色，状态栏文字由白变黑、
  压在深色玻璃上看不清。最小改法：把 forceDark = false 从 close() 开头挪到
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) 里（与 open() 的 0.52 对称）。
  本版按任务书「不要擅自大改」没有动，等你确认。
· 播放页往下拖到一半时，安全区那两条会被遮罩裁掉（只在拖动过程出现，松手即恢复）。
· 整首播放要求歌已在 Apple Music「资料库」；系统音量仍是 16 级。
