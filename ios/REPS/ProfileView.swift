import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @ObservedObject var store = Store.shared

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showEraseAlert = false
    @State private var toast: String?

    var body: some View {
        NavigationView {
            Form {
                basicSection
                if let m = store.bodyMetrics {
                    bodySection(m)
                }
                circumferenceSection
                strengthSection
                settingsSection
                dataSection
                aboutSection
            }
            .navigationTitle("我的")
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
                        toast = "读不到这个文件"
                        return
                    }
                    do {
                        let n = try store.importJSON(data)
                        toast = "已导入 \(n) 次训练记录"
                    } catch {
                        toast = "文件格式不对，不是 REPS 的备份"
                    }
                }
            }
            .alert("清空全部数据？", isPresented: $showEraseAlert) {
                Button("全部清空", role: .destructive) { store.eraseAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("训练历史、身体档案、歌单都会被删除。建议先导出备份。")
            }
            .overlay(alignment: .bottom) {
                if let t = toast {
                    Text(t)
                        .font(.subheadline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(24)
                        .padding(.bottom, 24)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { toast = nil }
                        }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 基本信息

    private var basicSection: some View {
        Section(header: Text("基本信息")) {
            Picker("性别", selection: Binding(get: { store.profile.sex },
                                              set: { var p = store.profile; p.sex = $0; store.profile = p })) {
                Text("男").tag("m")
                Text("女").tag("f")
            }
            .pickerStyle(.segmented)

            numberRow(title: "身高", unit: "cm",
                      value: Binding(get: { store.profile.height },
                                     set: { var p = store.profile; p.height = $0; store.profile = p }))
            numberRow(title: "体重", unit: "kg",
                      value: Binding(get: { store.profile.weight },
                                     set: { var p = store.profile; p.weight = $0; store.profile = p }))
            intRow(title: "年龄", unit: "岁",
                   value: Binding(get: { store.profile.age },
                                  set: { var p = store.profile; p.age = $0; store.profile = p }))
        }
    }

    // MARK: - 身体指标

    private func bodySection(_ m: Store.BodyMetrics) -> some View {
        Section(header: Text("身体指标"), footer: Text(m.advice)) {
            MetricRow(label: "BMI", value: String(format: "%.1f", m.bmi), note: m.bmiTag)
            MetricRow(label: "理想体重区间", value: "\(Int(m.idealLow))-\(Int(m.idealHigh))", unit: "kg")
            MetricRow(label: "基础代谢 BMR", value: "\(Int(m.bmr))", unit: "kcal")
            MetricRow(label: "每日消耗 TDEE", value: "\(Int(m.tdee))", unit: "kcal")
            if let lean = m.leanMass, let ffmi = m.ffmi {
                MetricRow(label: "去脂体重", value: String(format: "%.1f", lean), unit: "kg")
                MetricRow(label: "FFMI", value: String(format: "%.1f", ffmi), note: m.ffmiTag)
            }
            if let lose = m.fatToLose, lose > 0 {
                MetricRow(label: "减到 15% 体脂需减", value: String(format: "%.1f", lose), unit: "kg")
            }
        }
    }

    // MARK: - 围度估体脂

    private var circumferenceSection: some View {
        Section(header: Text("围度估体脂"),
                footer: Text("美国海军公式，误差约 ±3%。量的时候软尺贴皮肤、不要勒紧，早上空腹量最稳定。")) {
            numberRow(title: "颈围", unit: "cm",
                      value: Binding(get: { store.profile.neck },
                                     set: { var p = store.profile; p.neck = $0; store.profile = p }))
            numberRow(title: "腰围", unit: "cm",
                      value: Binding(get: { store.profile.waist },
                                     set: { var p = store.profile; p.waist = $0; store.profile = p }))
            if store.profile.sex == "f" {
                numberRow(title: "臀围", unit: "cm",
                          value: Binding(get: { store.profile.hip },
                                         set: { var p = store.profile; p.hip = $0; store.profile = p }))
            }
            numberRow(title: "体脂率", unit: "%",
                      value: Binding(get: { store.profile.bodyFat },
                                     set: { var p = store.profile; p.bodyFat = $0; store.profile = p }))
            Button {
                if let bf = store.estimateBodyFat() {
                    toast = "估算体脂 \(String(format: "%.1f", bf))%"
                } else {
                    toast = "围度填得不完整或数值不合理"
                }
            } label: {
                Label("用围度计算体脂", systemImage: "function")
            }
        }
    }

    // MARK: - 力量水平

    private var strengthSection: some View {
        Section(header: Text("力量水平"),
                footer: Text("填 1RM（一次能举起的最大重量）。倍数比绝对重量更公平——体重变了要重新比。男性中级线：卧推 1× 体重、深蹲 1.5×、硬拉 1.75×。")) {
            numberRow(title: "卧推 1RM", unit: "kg",
                      value: Binding(get: { store.profile.bench },
                                     set: { var p = store.profile; p.bench = $0; store.profile = p }))
            numberRow(title: "深蹲 1RM", unit: "kg",
                      value: Binding(get: { store.profile.squat },
                                     set: { var p = store.profile; p.squat = $0; store.profile = p }))
            numberRow(title: "硬拉 1RM", unit: "kg",
                      value: Binding(get: { store.profile.dead },
                                     set: { var p = store.profile; p.dead = $0; store.profile = p }))
            ForEach(store.liftLevels) { l in
                MetricRow(label: l.name,
                          value: "\(String(format: "%.2f", l.ratio))×",
                          note: l.level)
            }
        }
    }

    // MARK: - 设置

    private var settingsSection: some View {
        Section(header: Text("训练设置"), footer: Text("完成一组后会自动按这个时长开始休息计时，到点响铃并震动；锁屏时由系统通知提醒。")) {
            Picker("默认组间休息", selection: Binding(get: { store.restSeconds },
                                                      set: { store.restSeconds = $0 })) {
                Text("60 秒").tag(60)
                Text("90 秒").tag(90)
                Text("120 秒").tag(120)
                Text("180 秒").tag(180)
                Text("240 秒").tag(240)
            }
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section(header: Text("数据"),
                footer: Text("所有数据只存在这台手机上，不上传任何服务器。换手机或重装前请先导出备份。")) {
            Button {
                showExporter = true
            } label: {
                Label("导出备份（JSON）", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("从备份恢复", systemImage: "square.and.arrow.down")
            }
            HStack {
                Text("历史训练")
                Spacer()
                Text("\(store.sessions.count) 次").foregroundColor(.secondary)
            }
            HStack {
                Text("累计容量")
                Spacer()
                Text("\(Int(store.totalVolume)) kg").foregroundColor(.secondary)
            }
            Button(role: .destructive) {
                showEraseAlert = true
            } label: {
                Text("清空全部数据")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("2.0.0 · SwiftUI 原生").foregroundColor(.secondary)
            }
            HStack {
                Text("动作库")
                Spacer()
                Text("\(store.library.moves.count) 个动作").foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 工具

    private func numberRow(title: String, unit: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: Binding(get: {
                guard let v = value.wrappedValue else { return "" }
                return v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
            }, set: { text in
                value.wrappedValue = Double(text.replacingOccurrences(of: ",", with: "."))
            }))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
            Text(unit).foregroundColor(.secondary)
        }
    }

    private func intRow(title: String, unit: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: Binding(get: {
                value.wrappedValue.map { String($0) } ?? ""
            }, set: { text in
                value.wrappedValue = Int(text)
            }))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
            Text(unit).foregroundColor(.secondary)
        }
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
