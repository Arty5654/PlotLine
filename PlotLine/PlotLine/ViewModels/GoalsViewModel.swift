import Foundation

// MARK: - Enums

enum GoalViewType {
    case weekly
    case longTerm
}

enum Priority: String, CaseIterable, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var sortIndex: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

// MARK: - Data Models

struct TaskItem: Identifiable, Codable {
    let id: Int
    var name: String
    var isCompleted: Bool
    var priority: Priority
    var isEditing: Bool? = false
    var dueDate: Date?
    var notificationsEnabled: Bool
    var notificationType: String?
    var notificationTime: Date?
    
    var isFinancialGoal: Bool = false
    var progress: Double? = nil // 0.0 to 1.0 (optional)
    var totalBudget: Double? = nil
    var totalCosts: Double? = nil

    /// saved with the goal on the server; the phone schedules them (GoalReminders)
    var reminders: [GoalReminder] = []

    /// set when this goal is a step of a long-term goal (checking one off checks off both)
    var longTermGoalId: UUID? = nil
    var longTermStepId: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, priority, isEditing, dueDate, notificationsEnabled, notificationType, notificationTime
        case isCompleted = "completed"
        case isFinancialGoal, progress, totalBudget, totalCosts
        case reminders, longTermGoalId, longTermStepId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        priority = try container.decode(Priority.self, forKey: .priority)
        isEditing = try? container.decode(Bool.self, forKey: .isEditing)
        dueDate = try? container.decode(Date.self, forKey: .dueDate)
        notificationsEnabled = (try? container.decode(Bool.self, forKey: .notificationsEnabled)) ?? false
        notificationType = try? container.decode(String.self, forKey: .notificationType)
        notificationTime = try? container.decode(Date.self, forKey: .notificationTime)
        isFinancialGoal = (try? container.decode(Bool.self, forKey: .isFinancialGoal)) ?? false
        progress = try? container.decode(Double.self, forKey: .progress)
        totalBudget = try? container.decode(Double.self, forKey: .totalBudget)
        totalCosts = try? container.decode(Double.self, forKey: .totalCosts)
        reminders = (try? container.decode([GoalReminder].self, forKey: .reminders)) ?? []
        longTermGoalId = try? container.decode(UUID.self, forKey: .longTermGoalId)
        longTermStepId = try? container.decode(UUID.self, forKey: .longTermStepId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(priority, forKey: .priority)
        try? container.encode(isEditing, forKey: .isEditing)
        try? container.encode(dueDate, forKey: .dueDate)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try? container.encode(notificationType, forKey: .notificationType)
        try? container.encode(notificationTime, forKey: .notificationTime)
        try container.encode(isFinancialGoal, forKey: .isFinancialGoal)
        try? container.encode(progress, forKey: .progress)
        try? container.encode(totalBudget, forKey: .totalBudget)
        try? container.encode(totalCosts, forKey: .totalCosts)
        try container.encode(reminders, forKey: .reminders)
        try container.encodeIfPresent(longTermGoalId, forKey: .longTermGoalId)
        try container.encodeIfPresent(longTermStepId, forKey: .longTermStepId)
    }

    init(
        id: Int,
        name: String,
        isCompleted: Bool,
        priority: Priority,
        isEditing: Bool? = false,
        dueDate: Date? = nil,
        notificationsEnabled: Bool = false,
        notificationType: String? = nil,
        notificationTime: Date? = nil,
        isFinancialGoal: Bool = false,
        progress: Double? = nil,
        totalBudget: Double? = nil,
        totalCosts: Double? = nil,
        reminders: [GoalReminder] = []
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.priority = priority
        self.isEditing = isEditing
        self.dueDate = dueDate
        self.notificationsEnabled = notificationsEnabled
        self.notificationType = notificationType
        self.notificationTime = notificationTime
        self.isFinancialGoal = isFinancialGoal
        self.progress = progress
        self.totalBudget = totalBudget
        self.totalCosts = totalCosts
        self.reminders = reminders
    }
}

/// One reminder on a weekly goal, in the person's local time. Relative ones follow the goal's due date.
struct GoalReminder: Codable, Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case dueDate, dayBefore, weekBefore, custom

        var label: String { label(anchor: "due date") }

        /// e.g. "On target date" for long-term goals
        func label(anchor: String) -> String {
            switch self {
            case .dueDate: return "On \(anchor)"
            case .dayBefore: return "1 day before"
            case .weekBefore: return "1 week before"
            case .custom: return "Custom date"
            }
        }

        var daysBefore: Int? {
            switch self {
            case .dueDate: return 0
            case .dayBefore: return 1
            case .weekBefore: return 7
            case .custom: return nil
            }
        }
    }

    var id: String = UUID().uuidString
    var kind: String          // a Kind, kept as text so a newer app's kinds don't break older ones
    var time: String          // "HH:mm"
    var date: String? = nil   // "yyyy-MM-dd", custom only

    var type: Kind? { Kind(rawValue: kind) }

    init(kind: Kind, time: String = "09:00", date: String? = nil) {
        self.kind = kind.rawValue
        self.time = time
        self.date = date
    }

    /// when it goes off, or nil if it can't be worked out (e.g. a relative reminder without a due date)
    func fireDate(dueDate: Date?, calendar: Calendar = .current) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let type else { return nil }
        let day: Date
        if let daysBefore = type.daysBefore {
            guard let dueDate, let d = calendar.date(byAdding: .day, value: -daysBefore, to: dueDate) else { return nil }
            day = d
        } else {
            guard let date, let d = Self.dayFormatter.date(from: date) else { return nil }
            day = d
        }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}



struct LongTermGoal: Identifiable, Codable {
    let id: UUID
    var title: String
    var steps: [LongTermStep]
    /// "yyyy-MM-dd", optional; relative reminders count back from it
    var targetDate: String? = nil
    var reminders: [GoalReminder] = []

    enum CodingKeys: String, CodingKey { case id, title, steps, targetDate, reminders }

    init(id: UUID, title: String, steps: [LongTermStep], targetDate: String? = nil, reminders: [GoalReminder] = []) {
        self.id = id
        self.title = title
        self.steps = steps
        self.targetDate = targetDate
        self.reminders = reminders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        steps = (try? c.decode([LongTermStep].self, forKey: .steps)) ?? []
        targetDate = try? c.decode(String.self, forKey: .targetDate)
        reminders = (try? c.decode([GoalReminder].self, forKey: .reminders)) ?? []
    }

    var target: Date? { targetDate.flatMap { GoalReminder.dayFormatter.date(from: $0) } }
    var completedSteps: Int { steps.filter(\.isCompleted).count }
    /// every step checked off (a goal with no steps isn't "done")
    var isDone: Bool { !steps.isEmpty && completedSteps == steps.count }
}

struct LongTermStep: Identifiable, Codable {
    let id: UUID
    var name: String
    var isCompleted: Bool
    /// set while this step is also a weekly goal
    var weeklyGoalId: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isCompleted = "completed"
        case weeklyGoalId
    }
}

struct LongTermGoalsResponse: Codable {
    let longTermGoals: [LongTermGoal]
    let archivedGoals: [LongTermGoal]?
}

struct GoalsResponse: Codable {
    let weeklyGoals: [TaskItem]
}

struct WeeklyCosts: Codable {
    let username: String
    let type: String
    let costs: [String: Double]
}

struct WeeklyBudget: Codable {
    let username: String
    let type: String
    let budget: [String: Double]
}

struct FinancialSummary: Codable {
    let totalCosts: Double
    let totalBudget: Double
}
