//
//  GroceryAPI.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

import Foundation
import SwiftUI

struct GroceryListAPI {
    static let baseURL = "\(BackendConfig.baseURLString)/api/groceryLists" // Replace with your actual backend URL
    
    // Function to create a new grocery list with the username
    static func createGroceryList(name: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/create-grocery-list") else {
            throw URLError(.badURL)
        }
        
        // Retrieve the logged-in username from UserDefaults
        guard let loggedInUsername = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)  // Handle this error as needed
        }
        
        // Create the grocery list model with username
        let groceryList = GroceryList(id: UUID(), name: name, items: [], username: loggedInUsername)
        
        // Encode the GroceryList model into JSON
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(groceryList)
        } catch {
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Assuming the response is a string with the created grocery list ID
            let responseString = String(data: data, encoding: .utf8) ?? "Success"
            return responseString
        } catch {
            throw error
        }
    }
    
    // Function to get grocery lists for a user
    static func getGroceryLists(username: String) async throws -> [GroceryList] {
        guard let url = URL(string: "\(baseURL)/get-grocery-lists/\(username)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Decode the response into an array of GroceryList objects
            let groceryLists = try JSONDecoder().decode([GroceryList].self, from: data)
            return groceryLists
        } catch {
            throw error
        }
    }
    
    // Function to fetch items for a given grocery list
    static func getItems(listId: String) async throws -> [GroceryItem] {
        // Retrieve the logged-in username from UserDefaults
        guard let loggedInUsername = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        // Construct the URL
        guard let url = URL(string: "\(baseURL)/\(listId)/items?username=\(loggedInUsername)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let items = try JSONDecoder().decode([GroceryItem].self, from: data)
        return items
    }
    
    // Function to add an item to the grocery list
    static func addItem(listId: String, item: GroceryItem) async throws {
        // Retrieve the logged-in username from UserDefaults
        guard let loggedInUsername = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        guard let url = URL(string: "\(baseURL)/\(listId)/items?username=\(loggedInUsername)") else {
            throw URLError(.badURL)
        }
        
        // Create the grocery item model with username
        let groceryItem = item
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(groceryItem)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    // Function to delete an item from the grocery list
    static func deleteItem(listId: String, itemId: String) async throws {
        // Retrieve the logged-in username from UserDefaults
        guard let loggedInUsername = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard let url = URL(string: "\(baseURL)/\(listId)/items/\(itemId)?username=\(loggedInUsername)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    // Function to toggle the checked state of an item in a grocery list
    static func toggleChecked(listId: String, itemId: String) async throws {
        // Retrieve the logged-in username from UserDefaults
        guard let loggedInUsername = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        // Construct the URL to toggle the checked state of an item
        guard let url = URL(string: "\(baseURL)/\(listId)/items/\(itemId)/toggle?username=\(loggedInUsername)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Ensure we get a successful response
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
        } catch {
            throw error
        }
    }
    
    // Function to update the order of items in a grocery list
    static func updateItemOrder(listId: String, reorderedItems: [GroceryItem]) async throws {
        guard let loggedInUsername = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard let url = URL(string: "\(baseURL)/\(listId)/items/order?username=\(loggedInUsername)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(reorderedItems)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    // Function to update an item in the grocery list
    static func updateItem(listId: String, itemId: String, updatedItem: GroceryItem) async throws {
        // Retrieve the logged-in username from UserDefaults
        guard let loggedInUsername = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        // Construct the URL for updating the item
        guard let url = URL(string: "\(baseURL)/\(listId)/items/\(itemId)?username=\(loggedInUsername)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"  // Using PUT to update the item
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encode the updated item data into JSON
        do {
            request.httpBody = try JSONEncoder().encode(updatedItem)
        } catch {
            throw error
        }
        
        // Send the request and handle the response
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check if the response is successful (status code 200-299)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    // Function to archive a grocery list
    static func archiveGroceryList(username: String, groceryList: GroceryList, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/archive/\(username)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(groceryList)
            request.httpBody = jsonData
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "Invalid response", code: 0, userInfo: nil)))
                return
            }
            
            if let data = data, let result = String(data: data, encoding: .utf8) {
                completion(.success(result))
            } else {
                completion(.failure(NSError(domain: "Data error", code: 0, userInfo: nil)))
            }
        }
        
        task.resume()
    }
    
    // Function to get archived grocery lists
    static func getArchivedGroceryLists(username: String, completion: @escaping (Result<[GroceryList], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/archived/\(username)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "Invalid response", code: 0, userInfo: nil)))
                return
            }
            
            if let data = data {
                do {
                    let archivedLists = try JSONDecoder().decode([GroceryList].self, from: data)
                    completion(.success(archivedLists))
                } catch {
                    completion(.failure(error))
                }
            } else {
                completion(.failure(NSError(domain: "Data error", code: 0, userInfo: nil)))
            }
        }
        
        task.resume()
    }
    
    // Function to restore an archived grocery list
    static func restoreGroceryList(username: String, groceryList: GroceryList, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/restore/\(username)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(groceryList)
            request.httpBody = jsonData
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "Invalid response", code: 0, userInfo: nil)))
                return
            }
            
            if let data = data, let result = String(data: data, encoding: .utf8) {
                completion(.success(result))
            } else {
                completion(.failure(NSError(domain: "Data error", code: 0, userInfo: nil)))
            }
        }
        
        task.resume()
    }
    
    // Function to generate a grocery list from a meal name
    static func generateGroceryListFromMeal(mealName: String) async throws -> String {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        let url = URL(string: "\(baseURL)/generate-from-meal")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the request body
        let requestBody: [String: String] = [
            "mealName": mealName,
            "username": username
        ]
        
        // Serialize the request body to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw error
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for a successful response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                // Try to get more info from response body
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                
                throw URLError(.badServerResponse)
            }
            
            // Return the response data as a string (which will be the list ID or incompatibility message)
            let resultString = String(data: data, encoding: .utf8) ?? ""
            return resultString
            
        } catch {
            throw error
        }
    }
    
    // Function to generate a meal suggestion from a grocery list
    static func generateMealFromList(listID: String, groceryListItems: [(name: String, quantity: Int)]) async throws -> String {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }

        let url = URL(string: "\(baseURL)/generate-meal-from-list")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create the request body with the grocery list and username
        let requestBody: [String: Any] = [
            "username": username,
            "listId": listID,
            "items": groceryListItems.map { ["name": $0.name, "quantity": $0.quantity] }
        ]
        
        // Serialize the request body to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw error
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for a successful response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                // Try to get more info from response body
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                throw URLError(.badServerResponse)
            }
            
            // Return the response data as a string (which will be the meal suggestion or incompatibility message)
            let resultString = String(data: data, encoding: .utf8) ?? ""
            return resultString
            
        } catch {
            throw error
        }
    }
    
    static func generateGroceryListFromGoal(goalTitle: String) async throws -> String {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        let url = URL(string: "\(baseURL)/generate-list-from-goal")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the request body with the goal title and username
        let requestBody: [String: String] = [
            "goal": goalTitle,
            "username": username
        ]
        
        // Serialize the request body to JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
        } catch {
            throw error
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for a successful response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            // Always log the response body for debugging
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            
            if !(200...299).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            
            // Extract title from response
            do {
                // Parse the outer JSON to get the data field
                guard let responseData = responseString.data(using: .utf8),
                      let jsonResponse = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let dataJsonString = jsonResponse["data"] as? String else {
                    return "Grocery List"
                }
                
                // Parse the inner JSON (data field) to get the title
                guard let dataJsonData = dataJsonString.data(using: .utf8),
                      let dataJson = try JSONSerialization.jsonObject(with: dataJsonData) as? [String: Any],
                      let title = dataJson["title"] as? String else {
                    return "Grocery List"
                }
                
                return title
            } catch {
                return "Grocery List" // Fallback title
            }
            
        } catch {
            throw error
        }
    }
}
