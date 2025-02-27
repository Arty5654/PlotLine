//
//  WeeklyGoals.swift
//  PlotLine
//
//  Created by Allen Chang on 2/25/25.
//

import SwiftUI

struct WeeklyGoalsView: View {
    @State private var tasks: [TaskItem] = []
    @State private var newTask: String = ""
    
    // Fetch the logged-in username from UserDefaults
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }

    var body: some View {
        NavigationView {
            VStack {
                Text("\(username)'s Weekly Goals")
                    .font(.title)
                    .bold()
                    .padding()

                HStack {
                    TextField("Enter a new task", text: $newTask)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .padding()
                }

                List {
                    ForEach(tasks.indices, id: \.self) { index in
                            if tasks[index].isEditing ?? false {
                                TextField("Edit task", text: $tasks[index].name, onCommit: {
                                    updateTask(task: tasks[index]) // Save changes
                                })
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            } else {
                                HStack {
                                    Text(tasks[index].name)
                                        .strikethrough(tasks[index].isCompleted)
                                        .foregroundColor(tasks[index].isCompleted ? .gray : .primary)

                                    Spacer()

                                    Button(action: {
                                        toggleTaskCompletion(task: tasks[index])
                                    }) {
                                        Image(systemName: tasks[index].isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(tasks[index].isCompleted ? .green : .gray)
                                            .font(.title2)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        tasks[index].isEditing?.toggle()
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteTask(at: IndexSet(integer: index))
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    .onDelete(perform: deleteTask)
                }
                .listStyle(PlainListStyle())

                // Reset Button
                Button(action: resetGoals) {
                    Text("Reset Weekly Goals")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .cornerRadius(10)
                        .padding()
                }

            }
            .onAppear(perform: fetchGoals) // Fetch goals when the view appears
        }
    }


    private func fetchGoals() {
        guard username != "Guest",
              let url = URL(string: "http://localhost:8080/api/goals/\(username)") else {
            print("⚠️ Invalid username or URL")
            return
        }

        print("📡 Fetching goals from: \(url)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }

            guard let data = data else {
                print("⚠️ No data received from backend")
                return
            }

            do {
                let jsonString = String(data: data, encoding: .utf8)
                print("📜 Raw JSON Response: \(jsonString ?? "No Data")")  // Print raw JSON

                let decodedResponse = try JSONDecoder().decode(GoalsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.tasks = decodedResponse.weeklyGoals
                    print("✅ Successfully loaded \(self.tasks.count) goals")
                }
            } catch {
                print("❌ Error decoding JSON: \(error)")
            }
        }.resume()
    }


    private func addTask() {
        guard !newTask.isEmpty else { return }

        let newTaskItem = TaskItem(id: Int.random(in: 1000...9999), name: newTask, isCompleted: false) // Generate random ID

        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)") else {
            print("❌ Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(newTaskItem)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding JSON: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }

            DispatchQueue.main.async {
                self.tasks.append(newTaskItem)
                self.newTask = "" // Clear text field after adding
            }
        }.resume()
    }


    private func toggleTaskCompletion(task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        // Toggle the completed state
        tasks[index].isCompleted.toggle()
        
        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/\(task.id)") else {
            print("❌ Invalid URL for updating task")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(tasks[index]) // Encode updated task
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding JSON: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }

            DispatchQueue.main.async {
                print("✅ Task completion updated successfully in the backend")
            }
        }.resume()
    }

    
    private func updateTask(task: TaskItem) {
        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/\(task.id)") else {
            print("❌ Invalid URL for updating task")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(task)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding JSON: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }

            DispatchQueue.main.async {
                if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[index].isEditing = false // Exit edit mode
                }
            }
        }.resume()
    }


    private func deleteTask(at offsets: IndexSet) {
        for index in offsets {
            let task = tasks[index]

            guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/\(task.id)") else {
                print("❌ Invalid URL for deleting task")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ Network error: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
                }

                DispatchQueue.main.async {
                    self.tasks.removeAll { $0.id == task.id } // Remove from UI
                }
            }.resume()
        }
    }
    
    private func resetGoals() {
        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/reset") else {
            print("❌ Invalid URL for resetting tasks")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }

            DispatchQueue.main.async {
                self.tasks.removeAll() // Clear UI
            }
        }.resume()
    }
    
    


}

// MARK: - Data Models

struct TaskItem: Identifiable, Codable {
    let id: Int
    var name: String
    var isCompleted: Bool
    var isEditing: Bool? = false // Used to track editing state in UI

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isCompleted = "completed" // Map backend key
    }
}



struct GoalsResponse: Codable {
    let weeklyGoals: [TaskItem]
}

struct WeeklyGoalsView_Previews: PreviewProvider {
    static var previews: some View {
        WeeklyGoalsView()
    }
}

#Preview {
    WeeklyGoalsView()
}


