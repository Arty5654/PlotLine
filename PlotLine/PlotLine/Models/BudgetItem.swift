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
