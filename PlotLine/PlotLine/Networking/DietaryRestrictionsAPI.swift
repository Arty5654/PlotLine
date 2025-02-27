//
//  DietaryRestrictionsAPI.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/26/25.
//

import Foundation

class DietaryRestrictionsAPI {
    
    static let shared = DietaryRestrictionsAPI()  // Singleton instance
    
    private let baseURL = "http://localhost:8080/api/dietary-restrictions"  // Replace with your actual server URL
    
    // Method to fetch dietary restrictions
    func getDietaryRestrictions(username: String, completion: @escaping (Result<DietaryRestrictions, Error>) -> Void) {
        let urlString = "\(baseURL)/get-dietary-restrictions/\(username)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Start the network request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NetworkError.noData))
                return
            }
            
            do {
                // Parse the response into the DietaryRestrictions model
                let dietaryRestrictions = try JSONDecoder().decode(DietaryRestrictions.self, from: data)
                completion(.success(dietaryRestrictions))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    // Method to update dietary restrictions
    func updateDietaryRestrictions(username: String, dietaryRestrictions: DietaryRestrictions, completion: @escaping (Result<String, Error>) -> Void) {
        let urlString = "\(baseURL)/update-dietary-restrictions/\(username)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            // Encode the dietaryRestrictions object to JSON
            let jsonData = try JSONEncoder().encode(dietaryRestrictions)
            request.httpBody = jsonData
        } catch {
            completion(.failure(error))
            return
        }
        
        // Start the network request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NetworkError.noData))
                return
            }
            
            do {
                // Since the response is just a string, decode it as a string
                if let responseMessage = String(data: data, encoding: .utf8) {
                    completion(.success(responseMessage))
                } else {
                    completion(.failure(NetworkError.noData))
                }
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }

}

// Custom error types
enum NetworkError: Error {
    case invalidURL
    case noData
}
