import SwiftUI

struct TrainView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var rest = RestTimer.shared

    @State private var showPicker = false
    @State private var showFinishAlert = false
    @State private var showDiscardAlert = false
    /// 组间歇时长设置（Stepper）面板
    @State private var showRestSetting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    exerciseCard

                    restSettingRow

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

                    sessionFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background { AppBackground() }
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
            .sheet(isPresented: $showRestSetting) {
                RestSettingSheet()
            }
            .onAppear {
                // 新开一次训练 = 进入 working 阶段，本组计时从 0 起
                let hadSession = store.current != nil
                store.ensureSession()
                if !hadSession { rest.beginWork() }
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
                    VStack(alignment: .leading, spacing: 9) {
                        Text("当前动作")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(ex.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineSpacing(2)
                            .foregroundColor(.primary)
                        if let last = last {
                            Text("上次 \(last.sets.count) 组 · 最重 \(formatWeight(last.maxWeight)) kg · 1RM \(String(format: "%.1f", last.bestE1RM)) kg")
                                .font(.caption)
                                .lineSpacing(2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("还没记录过，先找能标准做 8-12 次的重量")
                                .font(.caption)
                                .lineSpacing(2)
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

    // MARK: - 组间休息设置入口
    //
    // 点这一行（右侧就是当前时长，如「120s」）弹出 Stepper：步长 15s、范围 15–600s，
    // 直接写回 store.restSeconds（Store 内部会 clamp 到 15…600 并立即落盘）。
    // 休息中它就贴在绿色倒计时圈正上方；不休息时也一直可见，方便开练前先调好。

    private var restSettingRow: some View {
        SectionCard {
            Button {
                showRestSetting = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(RestStyle.ring)
                    Text("组间休息")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer(minLength: 8)
                    Text("\(store.restSeconds)s")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        // 只有图标用绿（休息标识），数字保持普通文字色 ——
                        // 训练页除休息圈 / 休息按钮 / 休息图标外不应再有绿色
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 阶段卡（working 蓝 / resting 绿）
    //
    // 两阶段状态机：
    //   working --「完成这一组」--> 记录一组 + resting --倒计时归零 /「跳过休息」--> working → 下一组
    // 所以：
    //   · 「完成」只在 working 出现；「跳过休息」只在 resting 出现；
    //   · working 阶段既没有「跳过」，也没有手动开始休息的时长按钮（时长只在 restSettingRow 里改）；
    //   · 圈：working 蓝色（本组用时，TimelineView 每秒刷新，不另开 Timer），resting 绿色（倒计时）。

    private var phaseCard: some View {
        SectionCard {
            HStack(spacing: 16) {
                phaseRing

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(phaseTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text(phaseSubtitle)
                            .font(.caption)
                            .lineSpacing(2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if rest.isResting {
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
                                Text("跳过休息")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .transition(.opacity)

                        Text("锁屏后到点由系统通知提醒")
                            .font(.system(size: 10))
                            .lineSpacing(2)
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    /// 圈：resting 绿倒计时 / working 蓝本组用时。切换用 .opacity 0.2s（外层 phaseCard 上的 animation）。
    @ViewBuilder
    private var phaseRing: some View {
        if rest.isResting {
            RestRing(progress: rest.progress,
                     text: rest.remainingText,
                     caption: "休息中",
                     color: RestStyle.ring)
                .scaleEffect(0.62)
                .frame(width: 118, height: 118)
                .transition(.opacity)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                // 本组用时：workStart 是这一组的起点，elapsed 直接算差值，
                // 不靠累加计数，锁屏回来也准
                let elapsed = max(0, ctx.date.timeIntervalSince(rest.workStart))
                RestRing(progress: elapsed.truncatingRemainder(dividingBy: 60) / 60,
                         text: clockText(elapsed),
                         caption: "本组用时",
                         color: WorkStyle.ring)
                    .scaleEffect(0.62)
                    .frame(width: 118, height: 118)
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
            return "调好重量和次数，点下面的「完成这一组」开始第一组"
        }
        let target = "目标 \(formatWeight(store.lastWeight)) kg × \(store.lastReps)"
        return rest.isResting
            ? "下一组 \(formatWeight(store.lastWeight)) kg × \(store.lastReps)"
            : target
    }

    private var setCount: Int {
        store.current == nil ? 0 : store.currentExercise.sets.count
    }

    /// 底部主按钮：working 蓝「完成这一组」/ resting 绿「跳过休息」，同一时刻只出现一个。
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
                Text("完成这一组")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .transition(.opacity)
        }
    }

    // MARK: - 组列表

    private var setListCard: some View {
        let ex = store.currentExercise
        return SectionCard(title: "本次已完成 \(ex.sets.count) 组") {
            if ex.sets.isEmpty {
                Text("还没有记录。调好重量和次数，做完一组点上面的按钮。")
                    .font(.subheadline)
                    .lineSpacing(3)
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
                        .padding(.vertical, 13)
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

// MARK: - 组间歇时长设置

/// 组间歇时长的 Stepper 面板：步长 15s、范围 15–600s。
/// 每次改动立刻写回 store.restSeconds（Store 内部会 clamp 到 15…600 并 save），
/// 所以不新增任何存储字段，杀掉 App 重开依然保持。
struct RestSettingSheet: View {
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    @State private var value: Int = 120

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("\(value)s")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(RestStyle.ring)

                Stepper(value: $value, in: 15...600, step: 15) {
                    Text("组间休息时长")
                        .font(.subheadline)
                }

                HStack(spacing: 8) {
                    ForEach([45, 60, 90, 120, 180], id: \.self) { s in
                        Button {
                            value = s
                        } label: {
                            Text("\(s)")
                                .font(.system(size: 12, weight: value == s ? .semibold : .regular))
                                .foregroundColor(value == s ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(
                                    Capsule().fill(value == s
                                                   ? RestStyle.ring
                                                   : Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }

                Text("完成一组后按这个时长开始倒计时。改动立即保存，下次「完成一组」生效。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .navigationTitle("组间休息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { value = store.restSeconds }
            .onChange(of: value) { v in
                store.restSeconds = v
            }
        }
        .presentationDetents([.height(360)])
    }
}
