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
            self?.forceDark = true
        }
    }

    func close() {
        pull = 0
        // 播放页此刻还铺满全屏，切换不可见
        forceDark = false
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
                VStack(spacing: 14) {
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
        return VStack(alignment: .leading, spacing: 6) {
            Text("当前动作")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(ex.name)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("已做 \(ex.sets.count) 组")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if let s = ex.sets.last {
                    Text("· 上一组 \(formatWeight(s.w)) kg × \(s.r)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glass(cornerRadius: 20, shadow: false)
    }

    // MARK: 休息

    private var restCard: some View {
        HStack(spacing: 14) {
            MiniRestRing(progress: rest.progress, text: rest.remainingText, size: 58)
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(14)
        .glass(cornerRadius: 20, shadow: false)
    }

    // MARK: 组列表

    private var setListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本次记录")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            let sets = store.currentExercise.sets
            if sets.isEmpty {
                Text("还没有记录，调好重量和次数点「完成一组」")
                    .font(.system(size: 12))
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
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
