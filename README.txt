REPS iOS 4.9.2（build 12）交付说明
======================================================================

一、安装包
----------------------------------------------------------------------
文件        REPS-4.9.2-unsigned.ipa
大小        929,281 字节（0.89 MB）
SHA-256     50c278b794798872b9022433b2eb890a66d59058096d49c2d5de956220bac5bb
MD5         457f1edafcb171f05d4c177cda41add7
直链        https://github.com/klein7syd/gym/releases/download/v4.9.2/REPS-4.9.2-unsigned.ipa
Release     https://github.com/klein7syd/gym/releases/tag/v4.9.2
构建        GitHub Actions run 40652509897（macos-latest，Xcode 26.6，iOS SDK 26.5）
版本        4.9.2 / build 12（上一版 4.9.1 / 11）
签名        未签名。Sideloadly 自签：Apple 官网版 iTunes + Apple ID，双重认证填专用密码；
            装完到 设置 → 通用 → VPN与设备管理 信任证书，iOS 16+ 还要开开发者模式。
            免费账号 7 天过期；重签时别先卸载 App，否则沙盒里的训练记录会一起没。

交付物三件：本文件（README.txt）、CodeReview.txt（本轮改动文件的完整代码）、上面的 IPA。


二、改了什么 / 为什么
----------------------------------------------------------------------
1）播放页下拉 / 关闭时的深浅色闪烁（根因）
   以前的状态：
   · 下拉期间 forceDark 还是 true，整个窗口是深色，底下露出来的 TabView 也是深色版；
   · 松手 → close() 里 forceDark = false，底下整页**当场**由深变浅 → 闪；
   · 播放页移出过渡带 .opacity，淡出的几帧会透出底下那层 → 再闪一次。
   原则：窗口配色的切换只能发生在「播放页仍完全盖满屏幕、位移≈0」的时刻。

   实现（PlayerPresenter）：
   · beginDismiss()：拖动**第一帧**（minimumDistance 8，位移只有 8pt，底下几乎没露出）
     就把窗口切回浅色。用 Transaction + disablesAnimations，避免这一下被动画拖成渐变。
   · cancelDismiss()：没拖够弹回时，0.36s（弹回 spring 是 response 0.34）后再置回 true。
     回调里复查 isOpen == true 且 pull == 0，否则不执行（这 0.36s 内可能已经关掉或又拖了）。
   · close()：先切浅色（同样 disablesAnimations），然后 asyncAfter(0.05) 再启动下滑动画，
     让配色切换先单独渲染一帧 —— 这一帧播放页还盖满屏，看不见。若 forceDark 已经是 false
     （拖动路径已经切过），就不再等，直接下滑。保留 isOpen 的 guard。
   · open()：0.52s 的延迟回调里加了 isOpen 复查，0.52s 内被关掉就不会再把窗口切成深色。

2）NowPlayingView 的移出过渡去掉淡出
   改成 .asymmetric(insertion: .move + .opacity, removal: .move(edge: .bottom))。
   只位移不淡出，就不会在半透明那几帧里透出底下那层。

3）专辑页行距（AlbumDetailView 与列表行）
   · trackRow：上下 9 → 13，曲名 .lineSpacing(3)，整行 .frame(minHeight: 52)，
     分隔线 padding(.leading, 56) 不变。
   · header：外层 VStack 12 → 16，内层 3 → 6，专辑名 .lineSpacing(3)、
     艺人·年份 .lineSpacing(2)，.padding(.top, 12) → 16。
   · actions：.padding(.top, 20) → 22，.padding(.bottom, 14) → 18。
   · trackList：.padding(.vertical, 4) → 6。
   · libraryRow（搜索结果）：上下 8 → 11，内层 VStack 2 → 4，分隔线 66 不变。
   · localRow（本地）：上下 8 → 11，内层 VStack 2 → 4。
   · albumTile：VStack 6 → 8，副标题再加 .padding(.top, 2)。

4）播放页 / 训练面板 / 训练页文字行距
   · NowPlayingView.titleBlock：VStack 2 → 5，歌名与艺人各 .lineSpacing(2)。
   · trainingBar：文字 VStack 4 → 6，外层 .padding(.vertical, 12) → 14，
     小按钮 VStack 8 → 9（按钮高度 31 不变）。
   · 因为内容变高，fixed 448 → 462（构成写在代码注释里）。
   · TrainingSheet：外层 VStack 14 → 16；动作卡 6 → 8、内边距 16 → 18、标题与副行 .lineSpacing(2)；
     休息卡 3 → 5、内边距 14 → 16；记录卡 10 → 12、行内上下 2 → 6、
     空状态 .lineSpacing(3)、内边距 16 → 18。
   · TrainView（任务书本次未给代码，按同样增量处理）：动作卡内层 6 → 9，动作名 / 上次记录 /
     提示各 .lineSpacing(2)；休息卡右列 10 → 12，说明文字 .lineSpacing(2)；
     组列表行上下 9 → 13，空状态提示 .lineSpacing(3)。没有改任何字号、颜色、布局结构。
     固定高度检查：TrainView 里只有休息时长胶囊（38×28）与小胶囊按钮是固定高度，
     它们没加行距、不会被截断，所以没有需要同比加大的固定高度。

5）版本号 4.9.1（11）→ 4.9.2（12）。


三、文件变更清单
----------------------------------------------------------------------
新增       无
删除       无
修改       ios/REPS/PlayerChrome.swift  beginDismiss / cancelDismiss / close / open 改造；TrainingSheet 行距
           ios/REPS/MusicView.swift      dismissDrag 接入 begin/cancel；标题区与训练卡行距、fixed 462；
                                         专辑详情 / 搜索结果行 / 本地行 / 专辑格子行距
           ios/REPS/REPSApp.swift        播放页移出过渡去掉 .opacity
           ios/REPS/TrainView.swift      训练页动作卡 / 休息卡 / 组列表行距
           ios/project.yml               版本号 4.9.2 / build 12
未动       CardClip（mask + ignoresSafeArea）、AppBackground、GlassBar、VolumeBar、
           MiniPlayerBar、QueueSheet、Info.plist、preferredColorScheme


四、参数含义
----------------------------------------------------------------------
beginDismiss()            拖动第一帧切浅色；仅 forceDark == true 时执行。
cancelDismiss()           弹回后 0.36s 再切回深色；回调复查 isOpen && pull == 0。
close() 里的 0.05s        先渲染一帧「已切浅色、播放页仍盖满」，再启动下滑。
open() 里的 0.52s         滑入 0.46s + 余量；回调复查 isOpen。
8（minimumDistance）      拖动 8pt 才认为开始；此时位移还很小，切色不可见。
0.34 / 0.36               弹回 spring response 与 cancelDismiss 延迟（0.36 略大于 0.34）。
260                       下拉满格距离（pull = h / 260）。
110 / 260（far 判定）     松手位移 > 110 或预测末端 > 260 就关闭。
34 - 20 * pull            底层卡片圆角（未改）。
0.94 + 0.06 * pull        底层卡片缩放（未改）。
0.42 * (1 - pull)         底层压暗（未改）。
462                       播放页除封面外的固定高度（原 448，构成见代码注释）。
340 / 0.82 / 24           封面尺寸上限、屏宽比、左右留白（未改）。
0.13                      播放页底色与卡片堆叠底 #212121（未改）。
MARKETING_VERSION / CURRENT_PROJECT_VERSION = 4.9.2 / 12


五、怎么测试（本次 6 步，① ② ③ 是关键）
----------------------------------------------------------------------
① 浅色模式：打开播放页 → 缓慢下拉到一半（先别松手，盯着底下露出来的那一页）→
   松手弹回 → 再下拉到底关闭。全程底下页面应该一直是浅色，中途和松手时都不应该闪、
   不应该出现「由深变浅」的跳变。
② 深色模式（设置 → 显示与亮度 → 深色）把 ① 再做一遍：底下页面应始终是深色，
   弹回后状态栏文字重新变白。
③ 点播放页左上角 ⌄ 按钮关闭（不走手势）：整段应该只有下滑动作，没有配色跳变。
④ 打开后 0.5s 内立刻关闭，连做 5 次：不应该出现「下一次打开时先黑一下」。
⑤ 视觉检查：专辑详情页（封面、专辑名、艺人·年份、曲目行）行距是否舒服；
   搜索结果行 / 本地行 / 专辑格子是否整齐；播放页标题与底部训练卡是否不再挤在一起；
   训练面板（从播放页训练卡点进去）和训练页（动作卡、组列表）行距是否一致。
⑥ 小屏：iPhone SE（或模拟器 iPhone SE 3rd）打开播放页，确认封面缩小但仍完整可见，
   进度条、控制排、音量条、训练卡都没有被挤出屏幕。
另：正常放歌、切歌、锁屏控制中心、训练页记组与休息计时各过一遍，确认没有回归。


六、已知限制
----------------------------------------------------------------------
· 未真机验证。CI 只验证了编译通过、包结构、Info.plist 版本号 4.9.2/12。
  「下拉 / 关闭时不再闪烁」是本版唯一的逻辑改动，无法用编译验证，
  必须由你在手机上确认 ① ② ③ 三步。
· pull 仍是 @Published，拖动时每帧都会让整个 RootTabView 重新求值
  （里面是 TabView + mask + scaleEffect + overlay）。本版按要求**只排查不改**，
  最小优化方案：把「卡片堆叠」那层抽成只观察 pull 的小视图，例如

      struct CardStack<Content: View>: View {
          @ObservedObject var player = PlayerPresenter.shared
          let content: Content
          var body: some View {
              content
                  .modifier(CardClip(active: player.isOpen, radius: 34 - 20 * player.pull))
                  .scaleEffect(player.isOpen ? 0.94 + 0.06 * player.pull : 1, anchor: .center)
                  .overlay { ... }
          }
      }

  根视图写成 CardStack { TabView { ... } }，这样每帧只重算这个小视图，不再牵动四个页面的 body。
  另外 mask 每帧重光栅化是主要成本；若真机上拖动掉帧，可再加 .drawingGroup()
  或改成 pull == 0 时不套 mask（但要注意别引入结构分支，那会重建视图）。
· 播放页拖动到一半时，安全区那两条会被 mask 裁掉（仅拖动过程，松手恢复）。
· 整首播放要求歌已在 Apple Music「资料库」；系统音量仍是 16 级。
