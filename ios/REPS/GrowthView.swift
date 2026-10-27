import SwiftUI

struct GrowthView: View {
    @ObservedObject var store = Store.shared
    @State private var detailSession: Session?
    @State private var activeMetrics: Set<Store.BodyMetricKey> = [.weight, .bodyFat]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewCard
                    bodyChartCard

                    if store.trainedExerciseNames.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.trainedExerciseNames, id: \.self) { name in
                            exerciseCard(name)
                        }
                    }

                    historySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 118)
            }
            .background(Color.clear)
            .navigationTitle("成长")
            .sheet(item: $detailSession) { s in
                SessionDetailView(session: s)
            }
        }
    }

    // MARK: - 总览

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                statBlock(value: formatNumber(store.weekVolume), unit: "kg", label: "本周总容量")
                vDivider
                statBlock(value: "\(store.weekSessionCount)", unit: "次", label: "本周训练")
                vDivider
                statBlock(value: "\(store.currentStreak)", unit: "周", label: "连续训练")
            }
            Text("容量 = 重量 × 次数 × 组数。想变强，先保证每周总容量不掉，再谈加重。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass()
    }

    private var vDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.8, height: 40)
    }

    private func statBlock(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    // MARK: - 身体数据曲线

    private var bodyChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("身体数据")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("横轴 · 健身第几天")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            MetricChartView(data: chartData)

            HStack(spacing: 7) {
                ForEach(Store.BodyMetricKey.allCases) { key in
                    metricChip(key)
                }
                Spacer(minLength: 0)
            }

            if activeMetrics.count > 2 {
                Text("左轴对应第一条曲线，右轴对应第二条；其余曲线按各自数值范围绘制，看趋势为主。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.bodyLog.count < 2 {
                Text("再多记录几天体重，曲线就会连起来。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .glass()
    }

    private var chartData: [Store.BodyMetricKey: [Store.ChartPoint]] {
        var out: [Store.BodyMetricKey: [Store.ChartPoint]] = [:]
        // Set 无序，按 allCases 固定顺序取，保证「左轴 = 体重、右轴 = 体脂」
        for key in Store.BodyMetricKey.allCases where activeMetrics.contains(key) {
            out[key] = store.series(key)
        }
        return out
    }

    private func metricChip(_ key: Store.BodyMetricKey) -> some View {
        let on = activeMetrics.contains(key)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if on {
                    if activeMetrics.count > 1 { activeMetrics.remove(key) }
                } else {
                    activeMetrics.insert(key)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(on ? key.color : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(key.title)
                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                    .foregroundColor(on ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(on ? key.color.opacity(0.16) : Color.primary.opacity(0.04))
                    .overlay(Capsule().strokeBorder(on ? key.color.opacity(0.35) : Color.clear, lineWidth: 0.8))
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("还没有完成的训练")
                .font(.system(size: 15, weight: .semibold))
            Text("去训练页做几组，点「结束训练并保存」，这里会出现每个动作的进步曲线和加重建议。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .glass()
    }

    // MARK: - 单动作进步

    private func exerciseCard(_ name: String) -> some View {
        let h = store.history(of: name)
        let values = h.map { $0.bestE1RM }
        let current = values.last ?? 0
        let previous = values.count > 1 ? values[values.count - 2] : nil
        let delta = previous.map { current - $0 }
        let totalSets = h.reduce(0) { $0 + $1.sets.count }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(h.count) 次训练 · \(totalSets) 组")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", current))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("1RM")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    if let d = delta {
                        Text("\(d >= 0 ? "▲" : "▼") \(String(format: "%.1f", abs(d)))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(d >= 0 ? .green : .red)
                    }
                }
            }

            Sparkline(values: values)

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                Text(store.suggestion(for: name))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
        }
        .padding(16)
        .glass()
    }

    // MARK: - 历史

    private var historySection: some View {
        let sessions = store.sessions.sorted { $0.date > $1.date }
        return Group {
            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("历史训练")
                        .font(.system(size: 15, weight: .semibold))

                    ForEach(Array(sessions.prefix(30).enumerated()), id: \.element.id) { i, s in
                        Button {
                            detailSession = s
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(dateString(s.date))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(s.exercises.map { $0.name }.joined(separator: "、"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(s.setCount) 组")
                                        .font(.system(size: 12))
                                        .foregroundColor(.primary)
                                    Text("\(formatNumber(s.volume)) kg")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < min(sessions.count, 30) - 1 { GlassDivider() }
                    }
                }
                .padding(16)
                .glass()
            }
        }
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: d)
    }

    private func formatNumber(_ v: Double) -> String {
        if v >= 10000 { return String(format: "%.1f万", v / 10000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - 单次训练详情

struct SessionDetailView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = Store.shared
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 0) {
                        infoBlock("\(session.setCount)", "组数")
                        smallDivider
                        infoBlock("\(Int(session.volume))", "总容量 kg")
                        smallDivider
                        infoBlock("\(session.exercises.count)", "动作")
                    }
                    .padding(16)
                    .glass()

                    ForEach(session.exercises) { ex in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(ex.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("最佳 1RM \(String(format: "%.1f", ex.bestE1RM)) kg")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            ForEach(Array(ex.sets.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { GlassDivider() }
                                HStack {
                                    Text("第 \(i + 1) 组")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(fmt(s.w)) kg × \(s.r) 次")
                                        .font(.system(size: 14, weight: .medium))
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(16)
                        .glass()
                    }

                    Button(role: .destructive) {
                        showDelete = true
                    } label: {
                        Text("删除这次训练")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .navigationTitle("训练详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("删除这次训练？", isPresented: $showDelete) {
                Button("删除", role: .destructive) {
                    store.deleteSession(session.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后成长页的统计会同步变化，不可恢复。")
            }
        }
    }

    private var smallDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.8, height: 36)
    }

    private func infoBlock(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", w) : String(format: "%.2f", w)
    }
}
