// WidgetIntents.swift — PlotLineWidgets target
// AppIntents for configurable widget settings.

import AppIntents
import WidgetKit

// MARK: - Goal Period

enum GoalPeriod: String, AppEnum {
    case weekly   = "Weekly"
    case longTerm = "Long-Term"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Goal Period")
    static var caseDisplayRepresentations: [GoalPeriod: DisplayRepresentation] = [
        .weekly:   "Weekly",
        .longTerm: "Long-Term",
    ]
}

struct GoalPeriodIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Goal Settings"
    static var description = IntentDescription("Choose which goals to display.")

    @Parameter(title: "Period", default: .weekly)
    var period: GoalPeriod
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
