//
//  BudgetItem.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/19/25.
//

import Foundation

struct BudgetItem: Identifiable, Codable {
    var id = UUID()
    let category: String
    var amount: String
}

struct WeeklyMonthlyCostResponse: Codable {
    let username: String
    let type: String
    let costs: [String: Double] // This ensures the costs are properly decoded
}

struct BudgetResponse: Codable {
    let username: String
    let type: String
    let budget: [String: Double]
}
