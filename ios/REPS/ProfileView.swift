import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProfileView: View {
    @ObservedObject var store = Store.shared

    private enum Field: Hashable {
        case height, weight, age, neck, waist, hip, bodyFat, bench, squat, dead
        case logWeight, logBodyFat
    }

    @FocusState private var focused: Field?

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showEraseAlert = false
    @State private var toast: String?

    // 补记身体数据
    @State private var logDate = Date()
    @State private var logWeight = ""
    @State private var logBodyFat = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    basicCard
                    bodyLogCard
                    if let m = store.bodyMetrics {
                        metricsCard(m)
                    }
                    circumferenceCard
                    strengthCard
                    settingsCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }
            )
            .navigationTitle("我的")
            .toolbar {
                if focused != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("收起") { hideKeyboard() }
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                KeyboardDoneBar()
            }
            .sheet(isPresented: $showExporter) {
                if let url = writeExportFile() {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: [.json], allowsMultiple: false) { urls in
                    guard let url = urls.first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else {
                        showToast("读不到这个文件")
                        return
                    }
                    do {
                        let n = try store.importJSON(data)
                        showToast("已导入 \(n) 次训练记录")
                    } catch {
                        showToast("文件格式不对，不是 REPS 的备份")
                    }
                }
            }
            .alert("清空全部数据？", isPresented: $showEraseAlert) {
                Button("全部清空", role: .destructive) { store.eraseAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("训练历史、身体档案、体重曲线、歌单都会被删除。建议先导出备份。")
            }
            .overlay(alignment: .bottom) {
                if let t = toast {
                    Text(t)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassInner(cornerRadius: 18)
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
        }
    }

    private static let sexOptions: [(String, String)] = [("m", "男"), ("f", "女")]

    private func hideKeyboard() {
        focused = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation { toast = nil }
        }
    }

    // MARK: - 基本信息

    private var basicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 6) {
                ForEach(Self.sexOptions, id: \.0) { item in
                    Button {
                        var p = store.profile
                        p.sex = item.0
                        store.profile = p
                    } label: {
                        Text(item.1)
                            .font(.system(size: 13, weight: store.profile.sex == item.0 ? .semibold : .regular))
                            .foregroundColor(store.profile.sex == item.0 ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                if store.profile.sex == item.0 {
                                    Capsule().fill(.ultraThinMaterial)
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.7))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassInner(cornerRadius: 22)

            inputRow("身高", unit: "cm", field: .height,
                     value: Binding(get: { store.profile.height }, set: { v in
                         var p = store.profile; p.height = v; store.profile = p
                     }))
            GlassDivider()
            inputRow("体重", unit: "kg", field: .weight,
                     value: Binding(get: { store.profile.weight }, set: { v in
                         var p = store.profile; p.weight = v; store.profile = p
                         if let w = v { store.logBody(weight: w, bodyFat: p.bodyFat) }
                     }))
            GlassDivider()
            intRow("年龄", unit: "岁", field: .age,
                   value: Binding(get: { store.profile.age }, set: { v in
                       var p = store.profile; p.age = v; store.profile = p
                   }))
            GlassDivider()
            inputRow("体脂率", unit: "%", field: .bodyFat,
                     value: Binding(get: { store.profile.bodyFat }, set: { v in
                         var p = store.profile; p.bodyFat = v; store.profile = p
                         if let bf = v { store.logBody(weight: p.weight, bodyFat: bf) }
                     }))

            Text("体重和体脂每改一次，会按当天记录一个点，成长页的曲线就来自这里。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass()
    }

    // MARK: - 记录身体数据（可选日期）

    private var bodyLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("记录身体数据")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("日期可选 · 能补记以前")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Text("日期")
                    .font(.system(size: 15))
                Spacer()
                DatePicker("", selection: $logDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
            .padding(.vertical, 2)

            GlassDivider()

            HStack(spacing: 8) {
                Text("体重")
                    .font(.system(size: 15))
                Spacer()
                TextField("—", text: $logWeight)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 82)
                    .focused($focused, equals: .logWeight)
                Text("kg")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
            .padding(.vertical, 3)

            GlassDivider()

            HStack(spacing: 8) {
                Text("体脂")
                    .font(.system(size: 15))
                Spacer()
                TextField("—", text: $logBodyFat)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 82)
                    .focused($focused, equals: .logBodyFat)
                Text("%")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
            .padding(.vertical, 3)

            Button {
                saveBodyLog()
            } label: {
                Label("保存到这一天", systemImage: "checkmark.circle")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .padding(.top, 4)

            if !store.bodyLog.isEmpty {
                GlassDivider()

                HStack {
                    Text("最近记录")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("共 \(store.bodyLog.count) 条")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)

                let recent = Array(store.bodyLog.suffix(6).reversed())
                ForEach(recent) { e in
                    HStack(spacing: 8) {
                        Text(dayText(e.date))
                            .font(.system(size: 13))
                        Text("第 \(store.fitnessDay(e.date)) 天")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let w = e.weight {
                            Text(String(format: "%.1f", w))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .monospacedDigit()
                            Text("kg")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if let bf = e.bodyFat {
                            Text(String(format: "%.1f%%", bf))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.32))
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            logDate = e.date
                            logWeight = e.weight.map { String(format: "%.1f", $0) } ?? ""
                            logBodyFat = e.bodyFat.map { String(format: "%.1f", $0) } ?? ""
                        } label: {
                            Label("填到上面的表单", systemImage: "square.and.pencil")
                        }
                        Button {
                            store.setProgramStart(e.date)
                            showToast("曲线起点改为 \(dayText(e.date))")
                        } label: {
                            Label("设为曲线第 1 天", systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            store.deleteBodyLog(id: e.id)
                        } label: {
                            Label("删除这条", systemImage: "trash")
                        }
                    }
                }
            }

            Text("成长页的体重/体脂曲线就是这些点。补记历史日期，曲线会立刻补上。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass()
    }

    private func saveBodyLog() {
        let w = Double(logWeight.replacingOccurrences(of: ",", with: ".")
                        .replacingOccurrences(of: "，", with: "."))
        let bf = Double(logBodyFat.replacingOccurrences(of: ",", with: ".")
                        .replacingOccurrences(of: "，", with: "."))
        let hasW = (w ?? 0) > 0
        let hasBF = (bf ?? 0) > 0
        guard hasW || hasBF else {
            showToast("体重和体脂至少填一项")
            return
        }

        let day = Calendar.current.startOfDay(for: logDate)
        store.logBody(weight: hasW ? w : nil, bodyFat: hasBF ? bf : nil, date: day)

        // 记的是最新一天，就顺手同步成档案里的当前值
        if let latest = store.bodyLog.last,
           Calendar.current.isDate(latest.date, inSameDayAs: day) {
            var p = store.profile
            if let w = w, w > 0 { p.weight = w }
            if let bf = bf, bf > 0 { p.bodyFat = bf }
            store.profile = p
        }

        logWeight = ""
        logBodyFat = ""
        hideKeyboard()
        showToast("已记录 \(dayText(day))")
    }

    private func dayText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    // MARK: - 身体指标

    private func metricsCard(_ m: Store.BodyMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("身体指标")
                .font(.system(size: 15, weight: .semibold))

            GlassRow(title: "BMI", value: String(format: "%.1f", m.bmi), note: m.bmiTag)
            GlassDivider()
            GlassRow(title: "理想体重区间", value: "\(Int(m.idealLow))-\(Int(m.idealHigh))", unit: "kg")
            GlassDivider()
            GlassRow(title: "基础代谢 BMR", value: "\(Int(m.bmr))", unit: "kcal")
            GlassDivider()
            GlassRow(title: "每日消耗 TDEE", value: "\(Int(m.tdee))", unit: "kcal")
            if let lean = m.leanMass, let ffmi = m.ffmi {
                GlassDivider()
                GlassRow(title: "去脂体重", value: String(format: "%.1f", lean), unit: "kg")
                GlassDivider()
                GlassRow(title: "FFMI", value: String(format: "%.1f", ffmi), note: m.ffmiTag)
            }
            if let lose = m.fatToLose, lose > 0 {
                GlassDivider()
                GlassRow(title: "减到 15% 体脂需减", value: String(format: "%.1f", lose), unit: "kg")
            }

            Text(m.advice)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(16)
        .glass()
    }

    // MARK: - 围度估体脂

    private var circumferenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("围度估体脂")
                .font(.system(size: 15, weight: .semibold))

            inputRow("颈围", unit: "cm", field: .neck,
                     value: Binding(get: { store.profile.neck }, set: { v in
                         var p = store.profile; p.neck = v; store.profile = p
                     }))
            GlassDivider()
            inputRow("腰围", unit: "cm", field: .waist,
                     value: Binding(get: { store.profile.waist }, set: { v in
                         var p = store.profile; p.waist = v; store.profile = p
                     }))
            if store.profile.sex == "f" {
                GlassDivider()
                inputRow("臀围", unit: "cm", field: .hip,
                         value: Binding(get: { store.profile.hip }, set: { v in
                             var p = store.profile; p.hip = v; store.profile = p
                         }))
            }

            Button {
                if let bf = store.estimateBodyFat() {
                    store.logBody(weight: store.profile.weight, bodyFat: bf)
                    showToast("估算体脂 \(String(format: "%.1f", bf))%")
                } else {
                    showToast("围度填得不完整或数值不合理")
                }
            } label: {
                Label("用围度计算体脂", systemImage: "function")
            }
            .buttonStyle(GlassButtonStyle())
            .padding(.top, 4)

            Text("美国海军公式，误差约 ±3%。软尺贴皮肤不要勒紧，早上空腹量最稳。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass()
    }

    // MARK: - 力量水平

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("力量水平")
                .font(.system(size: 15, weight: .semibold))

            inputRow("卧推 1RM", unit: "kg", field: .bench,
                     value: Binding(get: { store.profile.bench }, set: { v in
                         var p = store.profile; p.bench = v; store.profile = p
                     }))
            GlassDivider()
            inputRow("深蹲 1RM", unit: "kg", field: .squat,
                     value: Binding(get: { store.profile.squat }, set: { v in
                         var p = store.profile; p.squat = v; store.profile = p
                     }))
            GlassDivider()
            inputRow("硬拉 1RM", unit: "kg", field: .dead,
                     value: Binding(get: { store.profile.dead }, set: { v in
                         var p = store.profile; p.dead = v; store.profile = p
                     }))

            ForEach(store.liftLevels) { l in
                GlassDivider()
                GlassRow(title: l.name,
                         subtitle: "\(Int(l.weight)) kg",
                         value: String(format: "%.2f", l.ratio),
                         unit: "× 体重",
                         note: l.level)
            }

            Text("倍数比绝对重量更公平，体重变了要重新比。男性中级线：卧推 1× 体重、深蹲 1.5×、硬拉 1.75×。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass()
    }

    // MARK: - 设置

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("训练设置")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 6) {
                ForEach([60, 90, 120, 180], id: \.self) { s in
                    Button {
                        store.restSeconds = s
                    } label: {
                        Text("\(s)s")
                            .font(.system(size: 13, weight: store.restSeconds == s ? .semibold : .regular))
                            .foregroundColor(store.restSeconds == s ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                if store.restSeconds == s {
                                    Capsule().fill(.ultraThinMaterial)
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.7))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassInner(cornerRadius: 22)

            Text("完成一组后按这个时长开始休息。到点响铃震动，锁屏时由系统通知提醒。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass()
    }

    // MARK: - 数据

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("数据")
                .font(.system(size: 15, weight: .semibold))

            Button {
                showExporter = true
            } label: {
                Label("导出备份（JSON）", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(GlassButtonStyle())

            Button {
                showImporter = true
            } label: {
                Label("从备份恢复", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(GlassButtonStyle())

            GlassDivider()
            GlassRow(title: "历史训练", value: "\(store.sessions.count)", unit: "次")
            GlassDivider()
            GlassRow(title: "累计容量", value: "\(Int(store.totalVolume))", unit: "kg")
            GlassDivider()
            GlassRow(title: "体重记录", value: "\(store.bodyLog.count)", unit: "条")

            Button(role: .destructive) {
                showEraseAlert = true
            } label: {
                Text("清空全部数据")
                    .foregroundColor(.red)
            }
            .buttonStyle(GlassButtonStyle())
            .padding(.top, 2)

            Text("数据只存在这台手机上，不上传任何服务器。换手机或重装前先导出备份。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassRow(title: "版本", value: "4.0.0")
            GlassDivider()
            GlassRow(title: "界面", value: "Liquid Glass")
            GlassDivider()
            GlassRow(title: "动作库", value: "\(store.library.moves.count)", unit: "个")
        }
        .padding(16)
        .glass()
    }

    // MARK: - 输入行

    private func inputRow(_ title: String, unit: String, field: Field,
                          value: Binding<Double?>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15))
            Spacer()
            TextField("—", text: Binding(
                get: { doubleText(value.wrappedValue) },
                set: { text in
                    let clean = text
                        .replacingOccurrences(of: "，", with: ".")
                        .replacingOccurrences(of: ",", with: ".")
                    value.wrappedValue = clean.isEmpty ? nil : Double(clean)
                }))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .focused($focused, equals: field)
            Text(unit)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .leading)
        }
        .padding(.vertical, 5)
    }

    private func intRow(_ title: String, unit: String, field: Field,
                        value: Binding<Int?>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15))
            Spacer()
            TextField("—", text: Binding(
                get: { value.wrappedValue.map { String($0) } ?? "" },
                set: { text in value.wrappedValue = Int(text) }))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .focused($focused, equals: field)
            Text(unit)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .leading)
        }
        .padding(.vertical, 5)
    }

    private func doubleText(_ v: Double?) -> String {
        guard let v = v else { return "" }
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.1f", v)
    }

    private func writeExportFile() -> URL? {
        guard let data = store.exportJSON() else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let name = "REPS-backup-\(f.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }
}
