import SwiftUI
import UIKit

// MARK: - 安全区
//
// 播放页要铺满整屏（含状态栏 / 底部横条区域），所以它自己忽略安全区，
// 再按真实安全区把内容往里让 —— 否则 `.clipShape` 会按安全区内的 frame 裁剪，
// 上下各留一条黑边（4.7 的「重大 Bug」就是这么来的）。

enum SafeArea {
    /// 取不到窗口时的回退值：按灵动岛机型（top 59 / bottom 34）。
    /// 绝不能用 0 —— 0 会让播放页内容顶到状态栏和底部横条下面。
    private static let fallback = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    static var insets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // 优先前台活跃的场景，没有再退回任意一个
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let win = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        // 首帧可能还没布局：top == 0 视为「拿不到」，回退到灵动岛基准值
        guard let insets = win?.safeAreaInsets, insets.top > 0 else { return fallback }
        return insets
    }
}

// MARK: - 播放页的呈现方式
//
// 以前用 fullScreenCover：那一层是完全独立的窗口层，往下拖时下面什么都没有，
// 露出来就是大片黑色。改成在根视图里叠一张自己管理的卡片：
// 打开时底下的 TabView 稍微缩小并压暗，播放页从底部推上来，
// 往下拖的时候底下的菜单一直看得见 —— 就是 iOS 那种「回到上一级」的观感。

final class PlayerPresenter: ObservableObject {
    static let shared = PlayerPresenter()
    @Published var isOpen = false
    /// 下拉进度：0 = 完全打开，1 = 已经拉到底（松手就关）。
    /// 下层菜单靠它跟着渐进放大 / 变亮 / 变圆角，而不是等关闭动画才动一下。
    @Published var pull: CGFloat = 0
    /// 播放页开着时把整个 App 切到深色（状态栏文字才会转白）。
    /// 不能随手写 `.preferredColorScheme(.dark)`：那会在播放页还在滑入、菜单露在外面的
    /// 那 0.4 秒里把整个窗口换成深色，看起来就是一整块颜色闪一下。
    /// 所以改成「完全盖住之后再切、开始下滑之前就切回来」——两次切换都发生在被遮住的时候。
    @Published var forceDark = false

    private init() {}

    func open() {
        guard !isOpen else { return }
        // 先收键盘：键盘弹着的时候迷你播放条被顶到键盘上方，点它打开播放页，
        // 键盘不会自己消失，会跟着播放页一起浮在下面（还能点到搜索框）。
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        pull = 0
        withAnimation(.spring(response: 0.46, dampingFraction: 0.90)) {
            isOpen = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) { [weak self] in
            // 0.52s 内用户已经把它关掉了：不要再把窗口切成深色，
            // 否则下一次打开会在「已经盖满」之前就变成深色，露出来那一下就是闪。
            // 也不要在「用户已经在下拉」的时候切：beginDismiss 刚把窗口切成浅色，
            // 这里再切回深色，等于在拖动中途翻色 —— 正是要修的那道跳变。
            // （这种极端情况由 cancelDismiss 的延迟回调兜底：松手弹回后 0.36s 会补回深色。）
            guard let self = self, self.isOpen, !self.isDragging else { return }
            self.forceDark = true
        }
    }

    // MARK: 配色切换的三个时机

    /// 往下拖的**第一帧**：位移还只有 8pt 左右，底下几乎还没露出来，
    /// 在这一帧把窗口切回浅色谁也看不见。
    ///
    /// 为什么必须这么早（4.9.4 的结论）：下拉期间底下露出的是哪一版 TabView，
    /// 完全取决于 forceDark。如果拖动全程保持深色（4.9.3 的做法），露出来的就是深色版页面，
    /// 等松手后再切浅 —— 那一整页当场由深变亮，就是用户看到的「深色/亮色跳变」。
    /// 所以要在一开始就把配色定成最终的样子。
    ///
    /// 用关掉动画的 Transaction：preferredColorScheme 的变化一旦被动画带，
    /// 会变成一段 0.4s 的渐变，叠在手势上更花。
    func beginDismiss() {
        guard forceDark else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { forceDark = false }
    }

    /// 是否正在拖动。普通属性、不是 @Published —— 它只给 cancelDismiss 的延迟回调做守卫，
    /// 不需要触发任何视图刷新。
    private(set) var isDragging = false

    func setDragging(_ v: Bool) {
        isDragging = v
    }

    /// 没拖够、弹回原位：等弹回动画（response 0.34）走完再把窗口切回深色。
    /// 回调里要复查三件事：
    ///   · isOpen —— 这 0.36s 内可能已经被关掉；
    ///   · pull == 0 —— 确实已经回位；
    ///   · !isDragging —— 用户可能又开始拖了，那配色归 beginDismiss 管，不能被这里拉回深色。
    func cancelDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
            guard let self = self, self.isOpen, self.pull == 0, !self.isDragging else { return }
            self.forceDark = true
        }
    }

    func close() {
        guard isOpen else { return }
        // ★ 这里**不能**立刻 pull = 0：
        // pull 同时驱动下层的大小（0.97 + 0.03 * pull）和圆角（22 - 12 * pull）。
        // 手势拉到底时 pull 已经接近 1，如果关闭的一瞬间把它归零，
        // 下层会从「几乎原样」猛地缩回 0.97 的小卡片 —— 就是滑到底松手时的「跳一下」。
        // 所以先让 isOpen=false 的动画从当前 pull 继续插值，动画结束（0.6s）后再悄悄复位。
        // 先把窗口切回浅色。此刻播放页还盖满全屏，切了看不见。
        // 然后让配色先单独渲染一帧（0.05s），再启动下滑动画 ——
        // 这样播放页滑出的整个过程里，底下露出来的都是已经切好的浅色页面。
        if forceDark {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { forceDark = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.startDismissAnimation()
            }
        } else {
            // 拖动开始时已经切过浅色了，不用再等
            startDismissAnimation()
        }
        // 关闭动画（spring response 0.40）走完之后再复位 pull。
        // 此时 isOpen 已经是 false，CardClip 不再生效、缩放也是 1，
        // 所以这次复位在视觉上没有作用 —— 纯粹为下一次打开准备干净的起点。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, !self.isOpen else { return }
            self.pull = 0
        }
    }

    private func startDismissAnimation() {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.92)) {
            isOpen = false
        }
    }
}

// MARK: - 训练面板
//
// 从播放页的训练卡点进来。内容就是训练页那套（同一个 Store / RestTimer），
// 只是排得更紧凑，边听歌边记组不用跳回训练页。

struct TrainingSheet: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var rest = RestTimer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    exerciseCard

                    phaseCard
                        .animation(.easeInOut(duration: 0.2), value: rest.isResting)

                    HStack(spacing: 12) {
                        StepperField(label: "重量", unit: "kg",
                                     value: formatWeight(store.lastWeight),
                                     onMinus: { store.setWeight(store.lastWeight - 2.5) },
                                     onPlus: { store.setWeight(store.lastWeight + 2.5) })
                        StepperField(label: "次数", unit: "reps",
                                     value: "\(store.lastReps)",
                                     onMinus: { store.setReps(store.lastReps - 1) },
                                     onPlus: { store.setReps(store.lastReps + 1) })
                    }

                    primaryButton
                        .animation(.easeInOut(duration: 0.2), value: rest.isResting)

                    setListCard

                    if store.current != nil {
                        Button(role: .destructive) {
                            rest.skip()
                            store.finishSession()
                            dismiss()
                        } label: {
                            Text("结束本次训练")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 26)
            }
            .background { AppBackground() }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { store.ensureSession() }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    // MARK: 当前动作

    private var exerciseCard: some View {
        let ex = store.currentExercise
        return VStack(alignment: .leading, spacing: 8) {
            Text("当前动作")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(ex.name)
                .font(.system(size: 20, weight: .bold))
                .lineSpacing(2)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("已做 \(ex.sets.count) 组")
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundColor(.secondary)
                if let s = ex.sets.last {
                    Text("· 上一组 \(formatWeight(s.w)) kg × \(s.r)")
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glass(cornerRadius: 20, shadow: false)
    }

    // MARK: 阶段卡（working 蓝 / resting 绿）
    //
    // 和训练页同一个 RestTimer，所以阶段与读秒完全同步：
    // working 显示蓝色「本组用时」，resting 显示绿色倒计时 + 「+30 / 跳过」。

    private var phaseCard: some View {
        HStack(spacing: 14) {
            phaseRing

            VStack(alignment: .leading, spacing: 5) {
                Text(phaseTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(phaseSubtitle)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)

            if rest.isResting {
                // 休息中才有「+30 / 跳过」，「完成」不出现
                Button {
                    rest.add(seconds: 30)
                } label: {
                    Text("+30")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 48, height: 32)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(ScaleButtonStyle())
                Button {
                    rest.skip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(RestStyle.ring)
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(16)
        .glass(cornerRadius: 20, shadow: false)
    }

    @ViewBuilder
    private var phaseRing: some View {
        if rest.isResting {
            MiniRestRing(progress: rest.progress, text: rest.remainingText,
                         size: 58, color: RestStyle.ring)
                .transition(.opacity)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let elapsed = max(0, ctx.date.timeIntervalSince(rest.workStart))
                MiniRestRing(progress: elapsed.truncatingRemainder(dividingBy: 60) / 60,
                             text: clockText(elapsed),
                             size: 58,
                             color: WorkStyle.ring)
            }
            .transition(.opacity)
        }
    }

    private var phaseTitle: String {
        guard store.current != nil else { return "还没开始训练" }
        return rest.isResting ? "组间休息" : "第 \(setCount + 1) 组 · 训练中"
    }

    private var phaseSubtitle: String {
        guard store.current != nil else {
            return "调好重量和次数，点「完成一组」开始"
        }
        let target = "目标 \(formatWeight(store.lastWeight)) kg × \(store.lastReps)"
        return rest.isResting
            ? "下一组 \(formatWeight(store.lastWeight)) kg × \(store.lastReps)"
            : target
    }

    private var setCount: Int {
        store.current == nil ? 0 : store.currentExercise.sets.count
    }

    /// 主按钮：working 蓝「完成一组」/ resting 绿「跳过休息」，同一时刻只有一个
    @ViewBuilder
    private var primaryButton: some View {
        if rest.isResting {
            Button {
                rest.skip()
            } label: {
                Text("跳过休息")
            }
            .buttonStyle(GlassButtonStyle(prominent: true, tint: RestStyle.ring))
            .transition(.opacity)
        } else {
            Button {
                completeSet()
            } label: {
                Text("完成一组")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .transition(.opacity)
        }
    }

    // MARK: 组列表

    private var setListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本次记录")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            let sets = store.currentExercise.sets
            if sets.isEmpty {
                Text("还没有记录，调好重量和次数点「完成一组」")
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(sets.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text("\(formatWeight(s.w)) kg")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Text("× \(s.r)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                        Button {
                            store.deleteSet(s.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glass(cornerRadius: 20, shadow: false)
    }

    private func completeSet() {
        // 「完成」只在 working 阶段有效：休息中不能记组
        guard !rest.isResting else { return }
        let hadSession = store.current != nil
        _ = store.ensureSession()
        if !hadSession { rest.beginWork() }
        store.logSet(weight: store.lastWeight, reps: store.lastReps)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rest.start(seconds: store.restSeconds)
    }

    /// 秒数 → m:ss（本组用时）
    private func clockText(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
