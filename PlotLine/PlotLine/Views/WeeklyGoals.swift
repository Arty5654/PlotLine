//
//  WeeklyGoals.swift
//  PlotLine
//
//  Created by Allen Chang on 2/25/25.
//

import SwiftUI

struct WeeklyGoalsView: View {
    // Weekly goals state variables
    @State private var tasks: [TaskItem] = []
    @State private var newTask: String = ""
    @State private var newTaskPriority: Priority = .medium
    @State private var selectedPriorityFilter: Priority? = nil
    @State private var selectedView: GoalViewType = .weekly
    @State private var newTaskDueDate = Date()
    
    // Long-term goals state variables
    @State private var longTermGoals: [LongTermGoal] = []
    @State private var newLongTermTitle: String = ""
    @State private var newStep: String = ""
    @State private var newLongTermSteps: [String] = []



    
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
                
                // Weekly View
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
                        
                        DatePicker("Due Date", selection: $newTaskDueDate, displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())

                        
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
                                        
                                        if let dueDate = task.dueDate {
                                            Text("Due: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

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
                    
                // Long Term View
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Creation Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Create a Long-Term Goal")
                                    .font(.headline)

                                TextField("Enter goal title", text: $newLongTermTitle)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())

                                HStack {
                                    TextField("Enter a step", text: $newStep)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())

                                    Button(action: {
                                        guard !newStep.isEmpty else { return }
                                        newLongTermSteps.append(newStep)
                                        newStep = ""
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                }

                                if !newLongTermSteps.isEmpty {
                                    Text("Steps:")
                                        .font(.subheadline)
                                        .bold()

                                    ForEach(newLongTermSteps, id: \.self) { step in
                                        Text("• \(step)")
                                    }
                                }

                                Button(action: addLongTermGoal) {
                                    Text("Save Goal")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.green)
                                        .cornerRadius(10)
                                }

                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)

                            // Display Section
                            if !longTermGoals.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(longTermGoals) { goal in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(goal.title)
                                                .font(.title3)
                                                .bold()

                                            // Step List
                                            ForEach(goal.steps) { step in
                                                HStack {
                                                    Text(step.name)
                                                        .strikethrough(step.isCompleted)
                                                        .foregroundColor(step.isCompleted ? .gray : .primary)

                                                    Spacer()

                                                    Button(action: {
                                                        toggleLongStepCompletion(goalId: goal.id, stepId: step.id)
                                                    }) {
                                                        Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                                            .foregroundColor(step.isCompleted ? .green : .gray)
                                                            .font(.title2)
                                                    }
                                                }
                                            }

                                            // Progress Bar
                                            let completedSteps = goal.steps.filter { $0.isCompleted }.count
                                            let totalSteps = goal.steps.count
                                            let progress = totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : 0

                                            ProgressView(value: progress)
                                                .accentColor(.green)
                                                .padding(.top, 4)

                                            Text("\(Int(progress * 100))% completed")
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            Divider() // Divider between goals
                                        }
                                        .padding(.top, 8)
                                    }

                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                } // end else
                    
            }.onAppear {
                fetchGoals()
                fetchLongTermGoals()
            }
        }
    }
    
    private func toggleStepCompletion(goalId: UUID, stepId: UUID) {
        if let goalIndex = longTermGoals.firstIndex(where: { $0.id == goalId }) {
            if let stepIndex = longTermGoals[goalIndex].steps.firstIndex(where: { $0.id == stepId }) {
                longTermGoals[goalIndex].steps[stepIndex].isCompleted.toggle()
            }
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
                print("📜 Raw JSON Response: \(jsonString ?? "No Data")")

                let decoder = JSONDecoder()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd" // 👈 Match backend format
                decoder.dateDecodingStrategy = .formatted(formatter)

                let decodedResponse = try decoder.decode(GoalsResponse.self, from: data)
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
            priority: newTaskPriority,
            dueDate: newTaskDueDate
        )

        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)") else {
            print("❌ Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd" // 👈 Match backend format
        encoder.dateEncodingStrategy = .formatted(formatter)

        do {
            let jsonData = try encoder.encode(newTaskItem)
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
        tasks[index].isCompleted.toggle()

        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/\(task.id)/completion") else {
            print("❌ Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["isCompleted": tasks[index].isCompleted]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            print("❌ Error encoding body: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Update completion HTTP Status Code: \(httpResponse.statusCode)")
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
    
    private func fetchLongTermGoals() {
        guard username != "Guest",
              let url = URL(string: "http://localhost:8080/api/goals/\(username)/long-term") else {
            print("⚠️ Invalid username or URL")
            return
        }

        print("📡 Fetching long-term goals from: \(url)")

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
                print("📜 Raw Long-Term JSON Response: \(jsonString ?? "No Data")")

                let decodedResponse = try JSONDecoder().decode(LongTermGoalsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.longTermGoals = decodedResponse.longTermGoals
                    print("✅ Successfully loaded \(self.longTermGoals.count) long-term goals")
                }
            } catch {
                print("❌ Error decoding long-term goals JSON: \(error)")
            }
        }.resume()
    }

    private func addLongTermGoal() {
        guard !newLongTermTitle.isEmpty else { return }

        let newGoal = LongTermGoal(
            id: UUID(),
            title: newLongTermTitle,
            steps: newLongTermSteps.map {
                LongTermStep(id: UUID(), name: $0, isCompleted: false)
            }
        )

        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/long-term") else {
            print("❌ Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(newGoal)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding long-term goal JSON: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("Long Term Goals: 🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }

            DispatchQueue.main.async {
                self.longTermGoals.append(newGoal)
                self.newLongTermTitle = ""
                self.newLongTermSteps = []
            }
        }.resume()
    }
    
    private func toggleLongStepCompletion(goalId: UUID, stepId: UUID) {
        guard let goalIndex = longTermGoals.firstIndex(where: { $0.id == goalId }),
              let stepIndex = longTermGoals[goalIndex].steps.firstIndex(where: { $0.id == stepId }) else { return }

        // Toggle local state
        longTermGoals[goalIndex].steps[stepIndex].isCompleted.toggle()

        // Prepare backend update
        guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/long-term/\(goalId)/steps/\(stepId)") else {
            print("❌ Invalid URL for step update")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["isCompleted": longTermGoals[goalIndex].steps[stepIndex].isCompleted]

        do {
            let jsonData = try JSONEncoder().encode(payload)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding step completion update: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Step completion update status code: \(httpResponse.statusCode)")
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
    var dueDate: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isCompleted = "completed"
        case priority
        case dueDate
    }
}


struct LongTermGoal: Identifiable, Codable {
    let id: UUID
    var title: String
    var steps: [LongTermStep]
}

struct LongTermStep: Identifiable, Codable {
    let id: UUID
    var name: String
    var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isCompleted = "completed"
    }
}

struct LongTermGoalsResponse: Codable {
    let longTermGoals: [LongTermGoal]
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


