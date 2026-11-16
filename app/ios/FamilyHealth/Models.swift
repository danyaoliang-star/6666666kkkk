import Foundation

struct Account: Codable { let name: String; let username: String }
struct Member: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var relation: String
    var birthday: String
    var note: String
    var scopes: [String]
    func allows(_ scope: String) -> Bool { scopes.contains(scope) }
}
struct Indicator: Codable { let name: String; let unit: String; let group: String }
struct Observation: Codable, Identifiable {
    let id: Int; let code: String; let value: Double; let measuredAt: String
    let condition: String; let refLow: Double?; let refHigh: Double?; let note: String; let reportId: Int?
}
struct MedicalReport: Codable, Identifiable {
    let id: Int; let name: String; let mime: String; let createdAt: String
    let reportDate: String?; let ocrStatus: String; let ocrError: String?
    let testName: String?
    var title: String { testName.flatMap { $0.isEmpty ? nil : $0 } ?? name }
    var pending: Bool { ["queued", "processing", "analyzing"].contains(ocrStatus) }
}
struct DailyPlan: Codable, Identifiable {
    struct Log: Codable { let day: String; let state: String }
    let id: Int; let title: String; let kind: String; let start: String; let end: String; let note: String
    let logs: [Log]
    func state(on day: String) -> String { logs.first { $0.day == day }?.state ?? "未填写" }
}
struct Conversation: Codable, Identifiable { let id: Int; let title: String }
struct ChatMessage: Codable, Identifiable {
    struct Attachment: Codable, Identifiable {
        let reportId: Int; let name: String; let mime: String
        var id: Int { reportId }
    }
    let id: Int; let role: String; let content: String; let mode: String?
    let createdAt: String?; let attachments: [Attachment]
    let memoryProposal: JSONValue?
}
struct ChatReply: Codable { let messages: [ChatMessage] }
struct AccessGrant: Codable, Identifiable { let id: Int; let username: String; let scope: String }
struct CareGoal: Codable, Identifiable {
    let id: Int; let code: String; let name: String; let unit: String
    let low: Double?; let high: Double?; let condition: String; let source: String
    let goalDate: String; let state: String; let revision: Int; let comparison: String
    let latest: Observation?
}
struct Followup: Codable, Identifiable {
    let id: Int; let title: String; let dueDate: String; let note: String
    let state: String; let revision: Int; let daysUntil: Int
}
struct CareOverview: Codable {
    let goals: [CareGoal]; let followups: [Followup]; let reminders: [Followup]
    let today: String; let canWrite: Bool
}
enum HealthScope: String, Codable, CaseIterable, Identifiable {
    case steps, activeEnergy, exerciseTime, sleep, heartRate, bodyMass
    var id: String { rawValue }
    var name: String {
        switch self {
        case .steps: return "步数"
        case .activeEnergy: return "活动能量"
        case .exerciseTime: return "运动时长"
        case .sleep: return "睡眠"
        case .heartRate: return "心率"
        case .bodyMass: return "体重"
        }
    }
    var unit: String {
        switch self {
        case .steps: return "步"
        case .activeEnergy: return "千卡"
        case .exerciseTime: return "分钟"
        case .sleep: return "小时"
        case .heartRate: return "次/分"
        case .bodyMass: return "kg"
        }
    }
    var symbol: String {
        switch self {
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame.fill"
        case .exerciseTime: return "figure.run"
        case .sleep: return "moon.fill"
        case .heartRate: return "heart.fill"
        case .bodyMass: return "scalemass.fill"
        }
    }
    var explanation: String {
        switch self {
        case .heartRate, .bodyMass: return "当天最近一次测量"
        case .sleep: return "按当地日历日计算实际睡眠，重叠时段去重"
        default: return "设备当地日期的每日累计"
        }
    }
}
struct HealthReading: Codable, Identifiable {
    let code: HealthScope; let day: String; let value: Double
    var id: String { code.rawValue + day }
}
struct HealthSnapshot: Codable {
    let windowStart: String; let windowEnd: String; let timezone: String; let records: [HealthReading]
}
struct HealthConnection: Codable {
    let canConnect: Bool; let active: Bool; let scopes: [HealthScope]; let consentId: String?
    let lastSyncedAt: String?; let timezone: String; let windowEnd: String?; let records: [HealthReading]
}

/// Flexible values are used for evidence-heavy responses; data stays in native SwiftUI views.
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var string: String {
        switch self { case .string(let v): return v; case .number(let v): return displayNumber(v); default: return "" }
    }
    var int: Int { if case .number(let v) = self, v.isFinite, v >= Double(Int.min), v < Double(Int.max) { return Int(v) }; return 0 }
    var bool: Bool { if case .bool(let v) = self { return v }; return false }
    var optionalNumber: Double? { if case .number(let v) = self { return v }; return nil }
}
func displayNumber(_ value: Double?) -> String {
    guard let value = value else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...2)))
}
enum AppDates {
    static func day(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(_ value: String) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(value.prefix(10))) ?? Date()
    }
    static func serverToday() -> String { day(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!) }
    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.string(from: date)
    }
    static func measurement(_ value: String) -> Date {
        if let result = ISO8601DateFormatter().date(from: value) { return result }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let result = f.date(from: value) { return result }
        }
        return date(value)
    }
    static func monday(_ date: Date = Date()) -> Date {
        let namedDay = self.date(day(date, timeZone: TimeZone(secondsFromGMT: 28800)!))
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: namedDay)
        return calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: namedDay)!
    }
}
