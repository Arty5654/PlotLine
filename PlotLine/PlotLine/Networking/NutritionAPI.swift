//
//  NutritionAPI.swift
//  PlotLine
//

import Foundation
import UIKit

class NutritionAPI {

    static let shared = NutritionAPI()
    private let baseURL = "\(BackendConfig.baseURLString)/api/nutrition"

    // MARK: - Fetch entries for a date

    func fetchEntries(for date: Date) async throws -> NutritionEntry? {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }

        let dateKey = Self.dateKey(from: date)
        guard let url = URL(string: "\(baseURL)/\(username)/\(dateKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NutritionEntry.self, from: data)
    }

    // MARK: - Save entry for a date

    func saveEntry(_ entry: NutritionEntry) async throws {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }

        let dateKey = Self.dateKey(from: entry.date)
        guard let url = URL(string: "\(baseURL)/\(username)/\(dateKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(entry)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Analyze food photo via backend (GPT-4o Vision)

    func analyzeFoodPhoto(_ image: UIImage) async throws -> [FoodItem] {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        guard let url = URL(string: "\(baseURL)/analyze-food") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()
        // Add username field for trophy tracking
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"username\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(username)\r\n".data(using: .utf8)!)
        // Add image field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"food.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([FoodItem].self, from: data)
    }

    // MARK: - Barcode lookup via Open Food Facts (free, no API key needed)

    func lookupBarcode(_ barcode: String) async throws -> FoodItem? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,serving_size,nutriments") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(OpenFoodFactsProduct.self, from: data)

        guard let product = result.product, result.status == 1 else { return nil }

        let name = [product.brands, product.productName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " – ")

        let serving = product.servingSize ?? "1 serving"
        let n = product.nutriments

        // Prefer per-serving data, fall back to per-100g
        let cal = n?.energyKcalServing ?? n?.energyKcal100g ?? 0
        let pro = n?.proteinsServing ?? n?.proteins100g ?? 0
        let carb = n?.carbohydratesServing ?? n?.carbohydrates100g ?? 0
        let fat = n?.fatServing ?? n?.fat100g ?? 0

        return FoodItem(
            name: name.isEmpty ? "Unknown Product" : name,
            servingSize: serving,
            servings: 1,
            calories: cal,
            protein: pro,
            carbs: carb,
            fat: fat,
            source: .barcode
        )
    }

    // MARK: - Favorites & Saved Meals

    func fetchUserData() async throws -> NutritionUserData {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let url = URL(string: "\(baseURL)/\(username)/user-data") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if http.statusCode == 404 {
            return NutritionUserData(favorites: [], savedMeals: [])
        }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }

        return try JSONDecoder().decode(NutritionUserData.self, from: data)
    }

    func saveUserData(_ userData: NutritionUserData) async throws {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let url = URL(string: "\(baseURL)/\(username)/user-data") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(userData)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Helpers

    static func dateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
