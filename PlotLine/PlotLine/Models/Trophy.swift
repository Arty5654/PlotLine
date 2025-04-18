//
//  Trophy.swift
//  PlotLine
//
//  Created by Alex Younkers on 4/18/25.
//
import Foundation

struct Trophy: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let level: Int
    let progress: Int
    let thresholds: [Int]
    let earnedDate: Date
}
