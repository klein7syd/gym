import Foundation

// MARK: - 训练数据

struct SetEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var w: Double          // 重量 kg
    var r: Int             // 次数
    var date: Date = Date()

    /// Epley 公式估算 1RM
    var e1rm: Double { r > 0 ? w * (1 + Double(r) / 30.0) : 0 }
    var volume: Double { w * Double(r) }
}

struct ExerciseEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var sets: [SetEntry] = []

    var bestE1RM: Double { sets.map { $0.e1rm }.max() ?? 0 }
    var maxWeight: Double { sets.map { $0.w }.max() ?? 0 }
    var volume: Double { sets.reduce(0) { $0 + $1.volume } }
}

struct Session: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var exercises: [ExerciseEntry]

    var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

/// 正在进行中的训练
struct ActiveSession: Codable, Equatable {
    var date: Date = Date()
    var exercises: [ExerciseEntry] = []
    var index: Int = 0
}

// MARK: - 身体档案

struct BodyProfile: Codable, Equatable {
    var sex: String = "m"          // m / f
    var height: Double?            // cm
    var weight: Double?            // kg
    var age: Int?
    var bodyFat: Double?           // %
    var neck: Double?              // cm
    var waist: Double?             // cm
    var hip: Double?               // cm
    var bench: Double?             // 卧推 1RM kg
    var squat: Double?
    var dead: Double?
}

// MARK: - 音乐

struct Track: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var filename: String           // Documents/Music 下的文件名

    var url: URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("Music").appendingPathComponent(filename)
    }
}

// MARK: - 持久化根对象

struct PersistedState: Codable {
    var sessions: [Session] = []
    var current: ActiveSession? = nil
    var restSeconds: Int = 120
    var lastWeight: Double = 20
    var lastReps: Int = 10
    var profile: BodyProfile = BodyProfile()
    var playlist: [Track] = []
    var lastTrackIndex: Int = 0
}

// MARK: - 动作库（bundle 内 moves.json）

struct Move: Codable, Identifiable, Hashable {
    var id: String { n }
    let n: String                  // 中文名
    let en: String?
    let g: String                  // 肌群
    let eq: String?                // 器械
    let p: String?                 // 动作模式
    let mus: String?               // 目标肌肉
    let cue: [String]?             // 动作要领
    let err: [String]?             // 常见错误
    let alt: [String]?             // 替代动作
}

struct MoveLibrary: Codable {
    let groups: [String]
    let equip: [String]
    let patterns: [String]
    let moves: [Move]

    static func load() -> MoveLibrary {
        guard let url = Bundle.main.url(forResource: "moves", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lib = try? JSONDecoder().decode(MoveLibrary.self, from: data) else {
            return MoveLibrary(groups: ["胸", "背", "腿", "肩", "臂", "核心"],
                               equip: [], patterns: [], moves: [])
        }
        return lib
    }
}

// MARK: - 历史记录（用于成长页）

struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let sets: [SetEntry]
    let live: Bool

    var bestE1RM: Double { sets.map { $0.e1rm }.max() ?? 0 }
    var maxWeight: Double { sets.map { $0.w }.max() ?? 0 }
    var maxReps: Int { sets.map { $0.r }.max() ?? 0 }
    var volume: Double { sets.reduce(0) { $0 + $1.volume } }
}
