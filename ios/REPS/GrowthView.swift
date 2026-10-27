import SwiftUI

struct GrowthView: View {
    @ObservedObject var store = Store.shared
    @State private var detailSession: Session?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    overviewCard

                    if store.trainedExerciseNames.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.trainedExerciseNames, id: \.self) { name in
                            exerciseCard(name)
                        }
                    }

                    historySection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("成长")
            .sheet(item: $detailSession) { s in
                SessionDetailView(session: s)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 总览

    private var overviewCard: some View {
        SectionCard {
            HStack(spacing: 0) {
                statBlock(value: formatNumber(store.weekVolume), unit: "kg", label: "本周总容量")
                Divider().frame(height: 44)
                statBlock(value: "\(store.weekSessionCount)", unit: "次", label: "本周训练")
                Divider().frame(height: 44)
                statBlock(value: "\(store.currentStreak)", unit: "周", label: "连续训练")
            }
            Text("容量 = 重量 × 次数 × 组数。想变强，先保证每周总容量不掉，再谈加重。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statBlock(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        SectionCard {
            VStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text("还没有完成的训练")
                    .font(.headline)
                Text("去训练页做几组，点「结束训练并保存」，这里就会出现你的进步曲线和加重建议。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - 单动作进步

    private func exerciseCard(_ name: String) -> some View {
        let h = store.history(of: name)
        let values = h.map { $0.bestE1RM }
        let current = values.last ?? 0
        let previous = values.count > 1 ? values[values.count - 2] : nil
        let delta = previous.map { current - $0 }
        let totalSets = h.reduce(0) { $0 + $1.sets.count }

        return SectionCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text("\(h.count) 次训练 · \(totalSets) 组")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", current))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("1RM")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let d = delta {
                        Text("\(d >= 0 ? "▲" : "▼") \(String(format: "%.1f", abs(d)))")
                            .font(.caption)
                            .foregroundColor(d >= 0 ? .green : .red)
                    }
                }
            }

            Sparkline(values: values)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(store.suggestion(for: name))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - 历史

    private var historySection: some View {
        let sessions = store.sessions.sorted { $0.date > $1.date }
        return Group {
            if !sessions.isEmpty {
                SectionCard(title: "历史训练") {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.prefix(30).enumerated()), id: \.element.id) { i, s in
                            Button {
                                detailSession = s
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dateString(s.date))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text(s.exercises.map { $0.name }.joined(separator: "、"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(s.setCount) 组")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        Text("\(formatNumber(s.volume)) kg")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            if i < min(sessions.count, 30) - 1 { Divider() }
                        }
                    }
                }
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
        if v >= 10000 {
            return String(format: "%.1f万", v / 10000)
        }
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
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("日期")
                        Spacer()
                        Text(session.date, style: .date).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("总组数")
                        Spacer()
                        Text("\(session.setCount) 组").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("总容量")
                        Spacer()
                        Text("\(Int(session.volume)) kg").foregroundColor(.secondary)
                    }
                }
                ForEach(session.exercises) { ex in
                    Section(header: Text("\(ex.name) · 最佳 1RM \(String(format: "%.1f", ex.bestE1RM)) kg")) {
                        ForEach(Array(ex.sets.enumerated()), id: \.element.id) { i, s in
                            HStack {
                                Text("第 \(i + 1) 组")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(s.w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", s.w) : String(format: "%.2f", s.w)) kg × \(s.r) 次")
                            }
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        showDelete = true
                    } label: {
                        Text("删除这次训练")
                    }
                }
            }
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
}
