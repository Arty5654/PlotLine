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

    enum CodingKeys: String, CodingKey {
        case id, name, priority, isEditing, dueDate, notificationsEnabled, notificationType, notificationTime
        case isCompleted = "completed"
        case isFinancialGoal, progress, totalBudget, totalCosts
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
        totalCosts: Double? = nil
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
    }
}



struct LongTermGoal: Identifiable, Codable {
    let id: UUID
    var title: String
    var steps: [LongTermStep]
}

struct LongTermStep: Identifiable, Codable {
    let id: UUID
    var name: String
    var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isCompleted = "completed"
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
