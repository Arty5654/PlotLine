//
//  MealsAPI.swift
//  PlotLine
//
//  Created by Yash Mehta on 5/1/25.
//

import Foundation

struct Meal: Identifiable, Decodable {
    var id: String
    var mealName: String
    var ingredients: [String]
    var recipe: [String]
    var optionalToppings: [String]
    
    enum CodingKeys: String, CodingKey {
        case id = "mealID"
        case mealName, ingredients, recipe, optionalToppings
    }
}

class MealViewModel: ObservableObject {
    @Published var meals: [Meal] = []  // Array of meals instead of single meal
    
    static let baseURL = "http://localhost:8080/api/meals"
    
    func fetchMeals(username: String) async throws {
        guard let url = URL(string: "\(MealViewModel.baseURL)/\(username)/all") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Decode the response into an array of Meal objects
            let fetchedMeals = try JSONDecoder().decode([Meal].self, from: data)
            
            DispatchQueue.main.async {
                self.meals = fetchedMeals
            }
        } catch {
            print("Decoding error: \(error)")
            throw error
        }
    }
}
