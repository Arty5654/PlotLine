//
//  GoalsRouter.swift
//  PlotLine
//
//  Opens Goals on the right tab, with a specific goal open, when a goal reminder is tapped.
//  The request stays set until that goal's screen has shown it, so it also works when the
//  tap launches the app.
//

import Foundation
import Combine

@MainActor
final class GoalsRouter: ObservableObject {
    static let shared = GoalsRouter()

    struct Request: Equatable {
        let tab: GoalViewType
        let goalId: String // a weekly goal's number, or a long-term goal's UUID
    }

    @Published var request: Request?

    /// from a notification's userInfo (see GoalReminders)
    func open(_ userInfo: [AnyHashable: Any]) {
        guard userInfo["navigateTo"] as? String == "goals",
              let id = userInfo["goalId"] as? String else { return }
        request = Request(tab: userInfo["goalsTab"] as? String == "longTerm" ? .longTerm : .weekly, goalId: id)
    }
}
