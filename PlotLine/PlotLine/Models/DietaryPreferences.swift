//
//  DietaryPreferences.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/26/25.
//

struct DietaryRestrictions: Codable {
    var username: String
    var lactoseIntolerant: Bool
    var vegetarian: Bool
    var vegan: Bool
    var glutenFree: Bool
    var kosher: Bool
    var dairyFree: Bool
    var nutFree: Bool
}

struct Allergies: Codable {
    var username: String
    var allergies: [String]
}
