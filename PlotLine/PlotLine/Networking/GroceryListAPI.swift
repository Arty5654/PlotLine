//
//  GroceryAPI.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

import Foundation
import SwiftUI

struct GroceryListAPI {
    static let baseURL = "http://localhost:8080/api/groceryLists" // Replace with your actual backend URL
    
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

        // Assuming server responds with success message
        print("Item added: \(String(data: data, encoding: .utf8) ?? "")")
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

        // Assuming server responds with success message
        print("Item deleted: \(String(data: data, encoding: .utf8) ?? "")")
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

            // Print return message
            print("\(String(data: data, encoding: .utf8) ?? "")")
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

        // Assuming server responds with success message
        print("Items reordered: \(String(data: data, encoding: .utf8) ?? "")")
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

        // Assuming server responds with a success message
        print("Item updated successfully: \(String(data: data, encoding: .utf8) ?? "")")
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
    
    static func generateGroceryListFromMeal(mealName: String) async throws -> String {
        guard let username = UserDefaults.standard.string(forKey: "loggedInUsername") else {
            throw URLError(.userAuthenticationRequired)
        }
        
        let url = URL(string: "http://localhost:8080/api/groceryLists/generate-from-meal")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the request payload
        let payload: [String: String] = [
            "mealName": mealName,
            "username": username
        ]
        
        // Serialize the payload to JSON
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        // Perform the network request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for a successful response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Parse the response (the list ID is returned as a plain string)
        guard let listId = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        
        return listId
    }
}
