//
//  CostsRouter.swift
//  PlotLine
//
//  Opens Monthly Costs on a given day with a category ready to fill in, when a bill that changes
//  each month (utilities) reminds them it's due. The request stays set until Monthly Costs has
//  shown it, so it also works when the tap launches the app.
//

import Foundation
import Combine

@MainActor
final class CostsRouter: ObservableObject {
    static let shared = CostsRouter()

    struct Request: Equatable {
        let day: Date
        let category: String
    }

    @Published var request: Request?

    /// from a notification's userInfo (see EventReminders)
    func open(_ userInfo: [AnyHashable: Any]) {
        guard userInfo["navigateTo"] as? String == "costs",
              let day = (userInfo["costsDay"] as? String).flatMap(Plan.day),
              let category = userInfo["costsCategory"] as? String, !category.isEmpty else { return }
        request = Request(day: day, category: category)
    }
}
