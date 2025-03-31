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
    @State private var newTaskPriority: Priority = .medium
    @State private var selectedPriorityFilter: Priority? = nil
    @State private var selectedView: GoalViewType = .weekly


    
    // Fetch the logged-in username from UserDefaults
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Button(action: {
                        selectedView = .weekly
                    }) {
                        Text("Weekly")
                            .fontWeight(.semibold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(selectedView == .weekly ? Color.gray.opacity(0.8) : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        selectedView = .longTerm
                    }) {
                        Text("Long Term")
                            .fontWeight(.semibold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(selectedView == .longTerm ? Color.gray.opacity(0.8) : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                if selectedView == .weekly {
                    Picker("Priority Filter", selection: $selectedPriorityFilter) {
                        Text("All").tag(nil as Priority?)
                        ForEach(Priority.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level as Priority?)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Create a New Task")
                            .font(.headline)
                            .padding(.bottom, 2)
                        
                        TextField("Enter task name", text: $newTask)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        VStack(alignment: .leading) {
                            Text("Priority")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("Priority", selection: $newTaskPriority) {
                                ForEach(Priority.allCases, id: \.self) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        HStack {
                            Spacer()
                            Button(action: addTask) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Task")
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    let filteredTasks = tasks
                        .filter { selectedPriorityFilter == nil || $0.priority == selectedPriorityFilter }
                        .sorted {
                            $0.priority.sortIndex < $1.priority.sortIndex
                        }
                    
                    
                    List {
                        ForEach(filteredTasks, id: \.id) { task in
                            if task.isEditing ?? false {
                                VStack(alignment: .leading) {
                                    TextField("Edit task", text: Binding(
                                        get: {
                                            task.name
                                        },
                                        set: { newName in
                                            if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                                                tasks[i].name = newName
                                            }
                                        }
                                    ), onCommit: {
                                        updateTask(task: task)
                                    })
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    
                                    Picker("Priority", selection: Binding(
                                        get: {
                                            task.priority
                                        },
                                        set: { newPriority in
                                            if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                                                tasks[i].priority = newPriority
                                            }
                                        }
                                    )) {
                                        ForEach(Priority.allCases, id: \.self) { level in
                                            Text(level.rawValue).tag(level)
                                        }
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .padding(.top, 4)
                                }
                                .padding(.vertical, 6)
                            } else {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(task.name)
                                            .strikethrough(task.isCompleted)
                                            .foregroundColor(task.isCompleted ? .gray : .primary)
                                        
                                        Text("Priority: \(task.priority.rawValue)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        toggleTaskCompletion(task: task)
                                    }) {
                                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(task.isCompleted ? .green : .gray)
                                            .font(.title2)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                                            tasks[i].isEditing?.toggle()
                                        }
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteTaskById(task.id)
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
                    
                } else {
                    // Long Term Goals Placeholder
                        Spacer()
                        Text("No long-term goals yet")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .padding()
                        Spacer()
                }
                    
            }.onAppear(perform: fetchGoals) // Fetch goals when the view appears
        }
    }
    
    private func deleteTaskById(_ id: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        deleteTask(at: IndexSet(integer: index))
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

        let newTaskItem = TaskItem(
            id: Int.random(in: 1000...9999),
            name: newTask,
            isCompleted: false,
            priority: newTaskPriority
        )

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
                self.newTask = ""
                self.newTaskPriority = .medium
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

enum GoalViewType {
    case weekly
    case longTerm
}


enum Priority: String, CaseIterable, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var sortIndex: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}


struct TaskItem: Identifiable, Codable {
    let id: Int
    var name: String
    var isCompleted: Bool
    var priority: Priority
    var isEditing: Bool? = false

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isCompleted = "completed"
        case priority
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


