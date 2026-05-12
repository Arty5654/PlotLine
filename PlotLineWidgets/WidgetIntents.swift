// WidgetIntents.swift — PlotLineWidgets target
// AppIntents for configurable widget settings.

import AppIntents
import WidgetKit

// MARK: - Goal Entity (dynamic goal picker)

struct GoalEntity: AppEntity, Hashable {
    var id: Int
    var name: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Goal")
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
    static var defaultQuery = GoalEntityQuery()
}

struct GoalEntityQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [GoalEntity] {
        readGoalsData()
            .filter { identifiers.contains($0.id) }
            .map { GoalEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        readGoalsData()
            .filter { !$0.isFinancialGoal }
            .map { GoalEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Goal Selection Intent

struct GoalSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Goal"
    static var description = IntentDescription("Choose a specific goal to track, or leave empty to see an overview.")

    @Parameter(title: "Goal")
    var goal: GoalEntity?
}

// MARK: - Budget Period

enum BudgetPeriod: String, AppEnum {
    case weekly  = "Weekly"
    case monthly = "Monthly"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static var caseDisplayRepresentations: [BudgetPeriod: DisplayRepresentation] = [
        .weekly:  "Weekly",
        .monthly: "Monthly",
    ]
}

struct BudgetPeriodIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Budget Settings"
    static var description = IntentDescription("Choose which budget period to display.")

    @Parameter(title: "Period", default: .weekly)
    var period: BudgetPeriod
}
