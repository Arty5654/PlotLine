//
//  SleepSchedule.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/2/25.
//

import Foundation

struct SleepSchedule: Codable, Identifiable {
    var id: UUID = UUID()
    var wakeUpTime: Date
    var sleepTime: Date
    var username: String
    var createdAt: String?
    var updatedAt: String?
    
    init(id: UUID = UUID(), wakeUpTime: Date, sleepTime: Date, username: String? = nil) {
        self.id = id
        self.wakeUpTime = wakeUpTime
        self.sleepTime = sleepTime
        self.username = username ?? UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
    }
}
