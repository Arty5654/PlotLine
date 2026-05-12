// PlotLineWidgetBundle.swift — PlotLineWidgets target
// Main entry point for the widget extension. Declares all widgets.

import WidgetKit
import SwiftUI

@main
struct PlotLineWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        BudgetWidget()
        GoalsWidget()
        CombinedWidget()
    }
}
