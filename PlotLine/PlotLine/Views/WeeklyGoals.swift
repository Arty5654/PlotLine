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
                    ForEach(tasks) { task in
                        HStack {
                            Text(task.name)
                                .strikethrough(task.isCompleted)
                                .foregroundColor(task.isCompleted ? .gray : .primary)

                            Spacer()

                            Button(action: {
                                toggleTaskCompletion(task: task)
                            }) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.isCompleted ? .green : .gray)
                                    .font(.title2)
                            }
                        }
                    }
                    .onDelete(perform: deleteTask)
                }
                .listStyle(PlainListStyle())
                .onAppear(perform: fetchGoals) // Fetch goals when the view appears
            }
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
        tasks.append(TaskItem(id: Int(), name: newTask, isCompleted: false))
        newTask = ""
    }

    private func toggleTaskCompletion(task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()
        }
    }

    private func deleteTask(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
    }
}

// MARK: - Data Models

struct TaskItem: Identifiable, Codable {
    let id: Int  // Change from UUID to Int
    var name: String
    var isCompleted: Bool
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


