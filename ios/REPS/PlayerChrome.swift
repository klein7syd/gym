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
        pull = 0
        withAnimation(.spring(response: 0.46, dampingFraction: 0.90)) {
            isOpen = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) { [weak self] in
            // 0.52s 内用户已经把它关掉了：不要再把窗口切成深色，
            // 否则下一次打开会在「已经盖满」之前就变成深色，露出来那一下就是闪。
            guard let self = self, self.isOpen else { return }
            self.forceDark = true
        }
    }

    // 4.9.2 曾在这里放过 `beginDismiss()` / `cancelDismiss()`：拖动第一帧就把窗口切回浅色，
    // 弹回时再延迟切回深色。4.9.3 删掉了这两个方法 —— 拖动途中改整个窗口的 userInterfaceStyle
    // 会触发全窗口重绘，叠加拖动每帧刷新，本身就是一处肉眼可见的闪烁。
    // 现在拖动全程保持 forceDark = true（底下露出的 TabView 是深色版，但播放页和压暗层
    // 本来就是深色，视觉上是连续的），只在下面 close() 里、播放页快滑出去时才切回浅色。

    func close() {
        guard isOpen else { return }
        pull = 0
        // 先把播放页往下滑；等它基本滑出屏幕、底层 TabView 也快回到 scale 1 之后，
        // 再切回浅色 —— 那时切几乎看不见。
        // 顺序是「先动画，0.30s 后再切色」，和 4.9.2 的「先切色，0.05s 后再动画」正好相反：
        // 4.9.2 那套在拖动关闭时颜色切换发生在卡片刚被拉下、底下露出很多的时刻，会跳一下。
        startDismissAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self = self else { return }
            // 复查状态：这 0.30s 内用户可能又点开了（isOpen 又变 true），
            // 那就不能再把窗口切成浅色，否则状态栏会在深色播放页上变成黑字。
            guard !self.isOpen else { return }
            guard self.forceDark else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { self.forceDark = false }
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

                    if rest.isRunning { restCard }

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

                    Button {
                        completeSet()
                    } label: {
                        Text("完成一组")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))

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

    // MARK: 休息

    private var restCard: some View {
        HStack(spacing: 14) {
            MiniRestRing(progress: rest.progress, text: rest.remainingText, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text("组间休息")
                    .font(.system(size: 13, weight: .semibold))
                Text("结束后会自动提示")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
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
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 32)
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(16)
        .glass(cornerRadius: 20, shadow: false)
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
        _ = store.ensureSession()
        store.logSet(weight: store.lastWeight, reps: store.lastReps)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rest.start(seconds: store.restSeconds)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
