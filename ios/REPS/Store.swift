import Foundation
import Combine

/// 全局数据层：所有训练、档案、歌单数据都经这里读写。
/// 持久化为 Documents/reps.json，纯本地、离线可用。
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var state = PersistedState()
    let library = MoveLibrary.load()

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = dir.appendingPathComponent("reps.json")
        loadFromDisk()
    }

    // MARK: - 持久化

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let s = try? dec.decode(PersistedState.self, from: data) {
            state = s
        }
    }

    /// 防抖写盘：连续操作时 0.4 秒合并一次，避免每组都写文件。
    func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func writeNow() {
        saveWork?.cancel()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 会话

    var current: ActiveSession? { state.current }
    var sessions: [Session] { state.sessions }
    var profile: BodyProfile {
        get { state.profile }
        set { state.profile = newValue; save() }
    }
    var restSeconds: Int {
        get { state.restSeconds }
        set { state.restSeconds = max(15, min(600, newValue)); save() }
    }
    var lastWeight: Double { state.lastWeight }
    var lastReps: Int { state.lastReps }

    /// 确保有一条进行中的训练，没有就建一条。
    @discardableResult
    func ensureSession() -> ActiveSession {
        if let cur = state.current { return cur }
        var cur = ActiveSession()
        let first = library.moves.first?.n ?? "杠铃卧推"
        cur.exercises = [ExerciseEntry(name: first)]
        state.current = cur
        save()
        return cur
    }

    /// 只读：绝不在渲染期创建会话，避免触发「渲染中修改状态」。
    var currentExercise: ExerciseEntry {
        guard let cur = state.current, !cur.exercises.isEmpty else {
            return ExerciseEntry(name: library.moves.first?.n ?? "杠铃卧推")
        }
        let i = max(0, min(cur.index, cur.exercises.count - 1))
        return cur.exercises[i]
    }

    func setWeight(_ w: Double) {
        state.lastWeight = max(0, min(500, (w * 100).rounded() / 100))
        save()
    }

    func setReps(_ r: Int) {
        state.lastReps = max(0, min(100, r))
        save()
    }

    /// 记录一组，返回该动作目前总组数。
    @discardableResult
    func logSet(weight: Double, reps: Int) -> Int {
        let cur = ensureSession()
        var c = cur
        let i = max(0, min(c.index, c.exercises.count - 1))
        c.exercises[i].sets.append(SetEntry(w: weight, r: reps))
        state.current = c
        state.lastWeight = weight
        state.lastReps = reps
        save()
        return c.exercises[i].sets.count
    }

    func deleteSet(_ setID: UUID) {
        guard var c = state.current else { return }
        for i in c.exercises.indices {
            c.exercises[i].sets.removeAll { $0.id == setID }
        }
        state.current = c
        save()
    }

    func switchExercise(index: Int) {
        guard var c = state.current, c.exercises.indices.contains(index) else { return }
        c.index = index
        state.current = c
        save()
    }

    func addExercise(name: String) {
        var c = ensureSession()
        if let existing = c.exercises.firstIndex(where: { $0.name == name }) {
            c.index = existing
        } else {
            c.exercises.append(ExerciseEntry(name: name))
            c.index = c.exercises.count - 1
        }
        state.current = c
        save()
    }

    func removeExercise(at index: Int) {
        guard var c = state.current, c.exercises.indices.contains(index), c.exercises.count > 1 else { return }
        c.exercises.remove(at: index)
        c.index = max(0, min(c.index, c.exercises.count - 1))
        state.current = c
        save()
    }

    /// 结束训练：只保留有组数的动作，写入历史。
    @discardableResult
    func finishSession() -> Session? {
        guard let c = state.current else { return nil }
        let done = c.exercises.filter { !$0.sets.isEmpty }
        guard !done.isEmpty else {
            state.current = nil
            save()
            return nil
        }
        let session = Session(date: c.date, exercises: done)
        state.sessions.append(session)
        state.current = nil
        writeNow()
        return session
    }

    func discardSession() {
        state.current = nil
        save()
    }

    func deleteSession(_ id: UUID) {
        state.sessions.removeAll { $0.id == id }
        save()
    }

    // MARK: - 历史与统计

    /// 某动作的全部历史，按时间正序；进行中的那次标 live = true。
    func history(of name: String, includeLive: Bool = false) -> [HistoryPoint] {
        var out: [HistoryPoint] = []
        for s in state.sessions.sorted(by: { $0.date < $1.date }) {
            if let ex = s.exercises.first(where: { $0.name == name }), !ex.sets.isEmpty {
                out.append(HistoryPoint(date: s.date, sets: ex.sets, live: false))
            }
        }
        if includeLive, let c = state.current,
           let ex = c.exercises.first(where: { $0.name == name }), !ex.sets.isEmpty {
            out.append(HistoryPoint(date: c.date, sets: ex.sets, live: true))
        }
        return out
    }

    func lastSession(of name: String) -> HistoryPoint? {
        history(of: name).last
    }

    /// 出现过的动作名，按最近使用排序。
    var trainedExerciseNames: [String] {
        var latest: [String: Date] = [:]
        for s in state.sessions {
            for e in s.exercises where !e.sets.isEmpty {
                if let old = latest[e.name] {
                    if s.date > old { latest[e.name] = s.date }
                } else {
                    latest[e.name] = s.date
                }
            }
        }
        return latest.sorted { $0.value > $1.value }.map { $0.key }
    }

    /// 本周总容量（重量 × 次数，近 7 天）。
    var weekVolume: Double {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return state.sessions.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.volume }
    }

    var weekSessionCount: Int {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return state.sessions.filter { $0.date >= cutoff }.count
    }

    var totalVolume: Double { state.sessions.reduce(0) { $0 + $1.volume } }

    /// 连续训练周数（粗略：按自然周去重后向前数）。
    var currentStreak: Int {
        guard !state.sessions.isEmpty else { return 0 }
        let cal = Calendar.current
        var weeks = Set<String>()
        for s in state.sessions {
            let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.date)
            weeks.insert("\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)")
        }
        var streak = 0
        let cursor = Date()
        // 本周没练不算断，从上周开始数
        for offset in 0..<104 {
            let d = cal.date(byAdding: .weekOfYear, value: -offset, to: cursor) ?? cursor
            let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
            let key = "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
            if weeks.contains(key) {
                streak += 1
            } else if offset == 0 {
                continue
            } else {
                break
            }
        }
        return streak
    }

    /// 渐进超负荷建议。只统计已完成的历史，不把进行中的这次算进去。
    func suggestion(for name: String) -> String {
        let h = history(of: name)
        guard let last = h.last else {
            return "第一次做这个动作，先找一个能标准完成 8-12 次的重量。"
        }
        let sets = last.sets
        let maxR = sets.map { $0.r }.max() ?? 0
        let n = sets.count
        if maxR >= 12 && n >= 3 {
            return "上次 \(n) 组全部做到 12 次 → 下次加 2.5 kg，次数回落到 8-10 次重新爬。"
        }
        if maxR >= 10 && n >= 3 {
            return "已经摸到 10 次 → 同重量再挤 1-2 次，能稳定 12 次就加 1.25 kg。"
        }
        if n < 3 {
            return "上次只做了 \(n) 组 → 先把组数补到 3-4 组，容量比重量更优先。"
        }
        return "次数还没到 10 → 同一重量继续堆次数，别急着加重。"
    }

    // MARK: - 身体指标

    struct BodyMetrics {
        var bmi: Double
        var bmiTag: String
        var idealLow: Double
        var idealHigh: Double
        var bmr: Double
        var tdee: Double
        var leanMass: Double?
        var ffmi: Double?
        var ffmiTag: String?
        var fatToLose: Double?
        var advice: String
    }

    var bodyMetrics: BodyMetrics? {
        let p = state.profile
        guard let h = p.height, let w = p.weight, h > 0, w > 0 else { return nil }
        let m = h / 100
        let bmi = w / (m * m)
        let bmiTag = bmi < 18.5 ? "偏瘦" : bmi < 24 ? "正常" : bmi < 28 ? "超重" : "肥胖"
        let bmr = 10 * w + 6.25 * h - 5 * Double(p.age ?? 28) + (p.sex == "m" ? 5 : -161)
        let tdee = bmr * 1.55
        var lean: Double?
        var ffmi: Double?
        var tag: String?
        var lose: Double?
        if let bf = p.bodyFat, bf > 0, bf < 70 {
            let l = w * (1 - bf / 100)
            lean = l
            let f = l / (m * m)
            ffmi = f
            tag = f < 18 ? "普通" : f < 20 ? "有点基础" : f < 22 ? "不错" : f < 24 ? "很强" : "接近自然上限"
            lose = max(0, w - l / 0.85)
        }
        let advice = bmi >= 24
            ? "先控体脂再谈增肌。体重降 5-8% 之后，力量表现通常反而会涨。"
            : bmi < 18.5
                ? "偏瘦。每天热量盈余 +300 kcal，训练优先胸背腿这些大肌群。"
                : "体重在正常区间，可以进入增肌或塑形阶段。"
        return BodyMetrics(bmi: bmi, bmiTag: bmiTag,
                           idealLow: 18.5 * m * m, idealHigh: 24 * m * m,
                           bmr: bmr, tdee: tdee,
                           leanMass: lean, ffmi: ffmi, ffmiTag: tag, fatToLose: lose,
                           advice: advice)
    }

    struct LiftLevel: Identifiable {
        let id = UUID()
        let name: String
        let weight: Double
        let ratio: Double
        let level: String
    }

    var liftLevels: [LiftLevel] {
        let p = state.profile
        guard let w = p.weight, w > 0 else { return [] }
        let defs: [(String, Double?, [Double])] = [
            ("卧推", p.bench, [0.5, 0.75, 1.0, 1.5]),
            ("深蹲", p.squat, [0.75, 1.0, 1.5, 2.0]),
            ("硬拉", p.dead,  [1.0, 1.25, 1.75, 2.5])
        ]
        var out: [LiftLevel] = []
        for (name, value, std) in defs {
            guard let v = value, v > 0 else { continue }
            let r = v / w
            let lvl = r < std[0] ? "入门" : r < std[1] ? "初级" : r < std[2] ? "中级" : r < std[3] ? "进阶" : "精英"
            out.append(LiftLevel(name: name, weight: v, ratio: r, level: lvl))
        }
        return out
    }

    /// 美国海军体脂公式，返回 nil 表示输入不合法。
    func estimateBodyFat() -> Double? {
        let p = state.profile
        guard let neck = p.neck, let waist = p.waist, let h = p.height, neck > 0, waist > 0, h > 0 else { return nil }
        let bf: Double
        if p.sex == "m" {
            guard waist > neck else { return nil }
            bf = 495 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(h)) - 450
        } else {
            guard let hip = p.hip, hip > 0, waist + hip > neck else { return nil }
            bf = 495 / (1.29579 - 0.35004 * log10(waist + hip - neck) + 0.22100 * log10(h)) - 450
        }
        guard bf.isFinite, bf > 0, bf <= 60 else { return nil }
        var np = state.profile
        np.bodyFat = (bf * 10).rounded() / 10
        state.profile = np
        save()
        return np.bodyFat
    }

    // MARK: - 歌单

    var playlist: [Track] {
        get { state.playlist }
        set { state.playlist = newValue; save() }
    }
    var lastTrackIndex: Int {
        get { state.lastTrackIndex }
        set { state.lastTrackIndex = newValue; save() }
    }

    // MARK: - 导入导出

    func exportJSON() -> Data? {
        writeNow()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(state)
    }

    enum ImportError: Error { case badFormat }

    @discardableResult
    func importJSON(_ data: Data) throws -> Int {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let s = try? dec.decode(PersistedState.self, from: data) else {
            throw ImportError.badFormat
        }
        state = s
        writeNow()
        return s.sessions.count
    }

    func eraseAll() {
        state = PersistedState()
        writeNow()
    }
}
