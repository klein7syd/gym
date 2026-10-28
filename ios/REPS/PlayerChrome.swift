import SwiftUI

// MARK: - 播放页的呈现方式
//
// 以前用 fullScreenCover：那一层是完全独立的窗口层，往下拖时下面什么都没有，
// 露出来就是大片黑色。改成在根视图里叠一张自己管理的卡片：
// 打开时底下的 TabView 稍微缩小并压暗，播放页从底部推上来，
// 往下拖的时候底下的菜单一直看得见 —— 就是 iOS 那种「回到上一级」的观感。

final class PlayerPresenter: ObservableObject {
    static let shared = PlayerPresenter()
    @Published var isOpen = false

    private init() {}

    func open() {
        guard !isOpen else { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.90)) {
            isOpen = true
        }
    }

    func close() {
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
        .presentationDetents([.medium, .large])
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
