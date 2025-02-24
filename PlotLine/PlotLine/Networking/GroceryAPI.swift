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
}
