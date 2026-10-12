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

    /// The foods in a meal photo. `note` is optional detail from the person ("cooked in olive oil").
    func analyzeFoodPhoto(_ image: UIImage, note: String? = nil) async throws -> [PhotoFood] {
        // ~1600 px is plenty for the analysis and uploads much faster than a full-size photo
        guard let imageData = Self.resized(image, maxSide: 1600).jpegData(compressionQuality: 0.75) else {
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
        request.timeoutInterval = 90 // the AI looks closely, then each food is matched to USDA data

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("username", username) // trophy tracking
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { field("note", note) }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"food.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let limit = AILimitError.from(data, response) { throw limit }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([PhotoFood].self, from: data)
    }

    static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: - Barcode lookup via Open Food Facts (free, no API key needed)

    func lookupBarcode(_ barcode: String) async throws -> FoodItem? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,serving_size,serving_quantity,nutriments") else {
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

        // Prefer per-serving data, fall back to per-100g (with kJ→kcal conversion)
        let cal = n?.bestCaloriesServing ?? n?.bestCalories100g ?? 0
        let pro = n?.proteinsServing ?? n?.proteins100g ?? 0
        let carb = n?.carbohydratesServing ?? n?.carbohydrates100g ?? 0
        let fat = n?.fatServing ?? n?.fat100g ?? 0

        // If all nutrition values are 0, the product data is incomplete — try Nutritionix
        let allZero = cal == 0 && pro == 0 && carb == 0 && fat == 0
        if allZero {
            // Try Open Food Facts world + US databases don't have it → return with zeroes
            // so the user can at least see the product name and manually correct
            print("[Barcode] Product found but nutrition data is empty: \(name)")
        }

        return FoodItem(
            name: name.isEmpty ? "Unknown Product" : name,
            servingSize: serving,
            servings: 1,
            calories: round(cal * 10) / 10,
            protein: round(pro * 10) / 10,
            carbs: round(carb * 10) / 10,
            fat: round(fat * 10) / 10,
            source: .barcode
        )
    }

    // MARK: - Food search via USDA FoodData Central
    // Covers whole foods, raw/cooked meats, produce, and branded products. The server makes the
    // USDA request (its key never ships in the app) and passes USDA's answer through.

    /// Food search: detailed generic USDA foods first, then store brands (the server ranks them).
    func searchFoods(_ query: String) async throws -> [SearchFood] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "\(BackendConfig.baseURLString)/api/nutrition/foods")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard !trimmed.isEmpty, let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct Response: Decodable { let foods: [SearchFood] }
        return try JSONDecoder().decode(Response.self, from: data).foods
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
