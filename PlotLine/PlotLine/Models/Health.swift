//
//  Health.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/2/25.
//

import Foundation

struct HealthEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var wakeUpTime: Date
    var sleepTime: Date
    var hoursSlept: Int
    var mood: String
    var notes: String
}
