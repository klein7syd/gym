import SwiftUI

struct TrainView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var rest = RestTimer.shared

    @State private var showPicker = false
    @State private var showFinishAlert = false
    @State private var showDiscardAlert = false

    private let restOptions = [60, 90, 120, 180]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    exerciseCard

                    if rest.isRunning {
                        restCard
                    }

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

                    Button(action: completeSet) {
                        Text("完成一组")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))

                    setListCard

                    sessionFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 118)
            }
            .background(Color.clear)
            .navigationTitle("训练")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView()
            }
            .onAppear {
                store.ensureSession()
            }
        }
    }

    // MARK: - 当前动作

    private var exerciseCard: some View {
        let ex = store.currentExercise
        let last = store.lastSession(of: ex.name)
        return SectionCard {
            Button {
                showPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前动作")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(ex.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        if let last = last {
                            Text("上次 \(last.sets.count) 组 · 最重 \(formatWeight(last.maxWeight)) kg · 1RM \(String(format: "%.1f", last.bestE1RM)) kg")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("还没记录过，先找能标准做 8-12 次的重量")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if (store.current?.exercises.count ?? 0) > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array((store.current?.exercises ?? []).enumerated()), id: \.element.id) { i, e in
                            Button {
                                store.switchExercise(index: i)
                            } label: {
                                Text(e.name)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(i == (store.current?.index ?? 0)
                                                ? Color.accentColor.opacity(0.18)
                                                : Color(UIColor.tertiarySystemFill))
                                    .foregroundColor(i == (store.current?.index ?? 0) ? .accentColor : .secondary)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 休息

    private var restCard: some View {
        SectionCard {
            HStack(spacing: 16) {
                RestRing(progress: rest.progress, text: rest.remainingText)
                    .scaleEffect(0.62)
                    .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(restOptions, id: \.self) { s in
                            Button {
                                rest.start(seconds: s)
                                store.restSeconds = s
                            } label: {
                                Text("\(s)")
                                    .font(.system(size: 12, weight: s == rest.total ? .semibold : .regular))
                                    .foregroundColor(s == rest.total ? .white : .secondary)
                                    .frame(width: 38, height: 28)
                                    .background(
                                        Capsule().fill(s == rest.total
                                                       ? Color.accentColor
                                                       : Color.primary.opacity(0.06))
                                    )
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            rest.add(seconds: 30)
                        } label: {
                            Text("+30 秒")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Button {
                            rest.skip()
                        } label: {
                            Text("跳过")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    Text("锁屏后到点由系统通知提醒")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 组列表

    private var setListCard: some View {
        let ex = store.currentExercise
        return SectionCard(title: "本次已完成 \(ex.sets.count) 组") {
            if ex.sets.isEmpty {
                Text("还没有记录。调好重量和次数，做完一组点上面的按钮。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ex.sets.enumerated()), id: \.element.id) { i, s in
                        HStack {
                            Text("\(i + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 22, alignment: .leading)
                            Text("\(formatWeight(s.w)) kg × \(s.r)")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
                            Spacer()
                            Text("1RM \(String(format: "%.1f", s.e1rm))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 9)
                        if i < ex.sets.count - 1 { Divider() }
                    }
                }
                if let last = ex.sets.last {
                    Button {
                        store.deleteSet(last.id)
                    } label: {
                        Label("撤销上一组", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - 底部操作

    private var sessionFooter: some View {
        VStack(spacing: 10) {
            Button {
                showFinishAlert = true
            } label: {
                Text("结束训练并保存")
            }
            .buttonStyle(GlassButtonStyle())

            if store.current != nil {
                Button(role: .destructive) {
                    showDiscardAlert = true
                } label: {
                    Text("放弃本次训练")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert("结束本次训练？", isPresented: $showFinishAlert) {
            Button("保存", role: .none) {
                rest.skip()
                store.finishSession()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已完成的组会写入历史，用于成长页统计。")
        }
        .alert("放弃本次训练？", isPresented: $showDiscardAlert) {
            Button("放弃", role: .destructive) {
                rest.skip()
                store.discardSession()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本次记录的所有组都会被删除，不可恢复。")
        }
    }

    // MARK: - 动作

    private func completeSet() {
        _ = store.ensureSession()
        store.logSet(weight: store.lastWeight, reps: store.lastReps)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rest.start(seconds: store.restSeconds)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", w) : String(format: "%.2f", w)
    }
}

// MARK: - 动作选择

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = Store.shared

    @State private var search = ""
    @State private var group: String? = nil
    @State private var detail: Move?
    @State private var customName = ""

    private var filtered: [Move] {
        store.library.moves.filter { m in
            let matchGroup = group == nil || m.g == group
            let q = search.trimmingCharacters(in: .whitespaces)
            let matchSearch = q.isEmpty
                || m.n.localizedCaseInsensitiveContains(q)
                || (m.en ?? "").localizedCaseInsensitiveContains(q)
                || (m.mus ?? "").localizedCaseInsensitiveContains(q)
                || (m.eq ?? "").localizedCaseInsensitiveContains(q)
            return matchGroup && matchSearch
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(title: "全部", selected: group == nil) { group = nil }
                            ForEach(store.library.groups, id: \.self) { g in
                                filterChip(title: g, selected: group == g) { group = g }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                Section(header: Text("自定义动作")) {
                    HStack {
                        TextField("不在列表里？输入名字", text: $customName)
                        Button("添加") {
                            let n = customName.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            store.addExercise(name: n)
                            customName = ""
                            dismiss()
                        }
                        .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section(header: Text("共 \(filtered.count) 个动作")) {
                    ForEach(filtered) { m in
                        HStack {
                            Button {
                                store.addExercise(name: m.n)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(m.n).foregroundColor(.primary)
                                    Text("\(m.g) · \(m.eq ?? "-") · \(m.p ?? "-")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                detail = m
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索动作 / 肌肉 / 器械")
            .navigationTitle("选择动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $detail) { m in
                MoveDetailView(move: m)
            }
        }
    }

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color(UIColor.tertiarySystemFill))
                .foregroundColor(selected ? .white : .primary)
                .cornerRadius(18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 动作详情

struct MoveDetailView: View {
    let move: Move
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = Store.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(move.n).font(.title2).fontWeight(.bold)
                        if let en = move.en {
                            Text(en).font(.subheadline).foregroundColor(.secondary)
                        }
                        Text("\(move.g) · \(move.eq ?? "-") · \(move.p ?? "-")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let mus = move.mus {
                            Text(mus).font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let cue = move.cue, !cue.isEmpty {
                    Section(header: Text("动作要领")) {
                        ForEach(cue, id: \.self) { Text($0).font(.subheadline) }
                    }
                }
                if let err = move.err, !err.isEmpty {
                    Section(header: Text("常见错误")) {
                        ForEach(err, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                }
                if let alt = move.alt, !alt.isEmpty {
                    Section(header: Text("替代动作")) {
                        ForEach(alt, id: \.self) { Text($0).font(.subheadline) }
                    }
                }
            }
            .navigationTitle("动作详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("开始练") {
                        store.addExercise(name: move.n)
                        dismiss()
                    }
                }
            }
        }
    }
}
