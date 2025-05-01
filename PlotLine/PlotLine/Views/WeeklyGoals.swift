//
//  WeeklyGoals.swift
//  PlotLine
//
//  Created by Allen Chang on 2/25/25.
//

import SwiftUI

struct WeeklyGoalsView: View {
    @Binding var tasks: [TaskItem]
    @Binding var newTask: String
    @Binding var newTaskPriority: Priority
    @Binding var newTaskDueDate: Date
    @Binding var selectedPriorityFilter: Priority?
    @Binding var notificationsEnabled: Bool
    @Binding var notificationType: String
    @Binding var notificationTime: Date
    let username: String
    var calendarVM: CalendarViewModel
    let fetchGoals: () -> Void

    @State private var isFinancialGoalDeleted = false

    
    var body: some View {
        NavigationView {
            VStack {
                // Weekly View
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    
                    if notificationsEnabled {
                        Picker("Notification Type", selection: $notificationType) {
                            Text("Due Date").tag("dueDate")
                            Text("Priority-based").tag("priority")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        if notificationType == "custom" {
                            DatePicker("Select Time", selection: $notificationTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                    
                    
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
                        Button(action: addFinancialGoal) {
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                Text("Add Financial Goal")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                        .padding(.bottom, 8)
                        .padding(.horizontal)

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
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.name)
                                        .font(.headline)
                                        .strikethrough(task.isCompleted)
                                        .foregroundColor(task.isCompleted ? .gray : .primary)
                                    
                                    if task.isFinancialGoal, let progress = task.progress {
                                        ProgressView(value: progress)
                                            .progressViewStyle(LinearProgressViewStyle())
                                            .frame(height: 8)
                                            .padding(.trailing, 16)
                                        
                                        Text(String(format: "Progress: %.0f%%", progress * 100))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if let budget = task.totalBudget, let costs = task.totalCosts {
                                            Text(String(format: "Budget: $%.2f", budget))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(String(format: "Current Spend: $%.2f", costs))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Text("Priority: \(task.priority.rawValue)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if let dueDate = task.dueDate {
                                            Text("Due: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
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
                .onAppear {
                    fetchGoals()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.tasks.first(where: { $0.isFinancialGoal }) == nil {
                            let placeholderFinancialGoal = TaskItem(
                                id: Int.random(in: 1000...9999),
                                name: "Save for Weekly Expenses",
                                isCompleted: false,
                                priority: .medium,
                                isEditing: false,
                                dueDate: nil,
                                notificationsEnabled: false,
                                notificationType: nil,
                                notificationTime: nil,
                                isFinancialGoal: true,
                                progress: 0.0
                            )
                            self.tasks.append(placeholderFinancialGoal)
                        }

                        self.updateFinancialGoalProgress()
                    }

                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if granted {
                            print("🟢 Notification permission granted")
                        } else if let error = error {
                            print("🔴 Notification error: \(error.localizedDescription)")
                        }
                    }
                }

        }
    }
}
    
    private func deleteTaskById(_ id: Int) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            if tasks[index].isFinancialGoal {
                self.isFinancialGoalDeleted = true
            }

            guard let url = URL(string: "http://localhost:8080/api/goals/\(username)/\(id)") else {
                print("❌ Invalid DELETE URL")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ Network error during deletion: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("🗑️ DELETE status: \(httpResponse.statusCode)")
                }

                DispatchQueue.main.async {
                    tasks.remove(at: index)
                }
            }.resume()
        }
    }

    
    private func addTask() {
        guard !newTask.isEmpty else { return }
        
        let newTaskItem = TaskItem(
            id: Int.random(in: 1000...9999),
            name: newTask,
            isCompleted: false,
            priority: newTaskPriority,
            dueDate: newTaskDueDate,
            notificationsEnabled: notificationsEnabled,
            notificationType: notificationType,
            notificationTime: notificationTime
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
            
            // MARK: save goal to calendar
            DispatchQueue.main.async {
                
                calendarVM.createEvent(
                    title: "\(newTask)",
                    description: "Weekly Goal - Priority: \(newTaskPriority)",
                    startDate: newTaskDueDate,
                    endDate: newTaskDueDate,
                    eventType: "weekly-goal-\(newTask.lowercased())",
                    recurrence: "none",
                    invitedFriends: []
                )
            }
            
            DispatchQueue.main.async {
                self.tasks.append(newTaskItem)
                self.newTask = ""
                self.newTaskPriority = .medium
                
                scheduleNotification(for: newTaskItem)
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
                    calendarVM.deleteEventByType("weekly-goal-\(task.name.lowercased())")
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
    
    func scheduleNotification(for task: TaskItem) {
        print("🔍 notificationsEnabled for \(task.name): \(task.notificationsEnabled)")
        guard task.notificationsEnabled else {
            print("🔕 Notifications disabled for task: \(task.name)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(task.name)"
        content.body = "Your goal \"\(task.name)\" is due soon!"
        content.sound = .default
        
        var triggerDate: Date?
        
        let now = Date()
        let calendar = Calendar.current
        
        switch task.notificationType {
        case "dueDate":
            if let dueDate = task.dueDate {
                if calendar.isDate(dueDate, inSameDayAs: now) {
                    triggerDate = now.addingTimeInterval(5) // test: due today = 5 seconds
                } else {
                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                    dateComponents.hour = 9
                    dateComponents.minute = 0
                    triggerDate = calendar.date(from: dateComponents)
                }
            }
            
        case "priority":
            switch task.priority {
            case .high:
                triggerDate = now.addingTimeInterval(5) // ⏱️ high = 5s
            case .medium:
                triggerDate = now.addingTimeInterval(10) // ⏱️ medium = 10s
            case .low:
                triggerDate = now.addingTimeInterval(60 * 60) // ⏱️ low = 1 hour
            }
            
        case "custom":
            if let customTime = task.notificationTime {
                triggerDate = customTime
            }
            
        default:
            print("⚠️ Unknown notificationType: \(task.notificationType ?? "nil")")
        }
        
        
        guard let date = triggerDate else {
            print("⚠️ Could not determine notification time for task: \(task.name)")
            return
        }
        
        print("🟡 Scheduling notification for \(task.name) at \(date)")
        
        let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "\(task.id)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔴 Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("✅ Notification scheduled for task: \(task.name)")
            }
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print("✅ Notifications permission granted: \(granted)")
            }
        }
    }
    
    private func addFinancialGoal() {
        fetchFinancialSummary { summary in
            guard let summary = summary else {
                print("❌ Failed to fetch financial summary")
                return
            }

            let newTaskItem = TaskItem(
                id: Int.random(in: 1000...9999),
                name: "Save for Weekly Expenses",
                isCompleted: false,
                priority: .medium,
                dueDate: nil,
                notificationsEnabled: false,
                notificationType: nil,
                notificationTime: nil,
                isFinancialGoal: true,
                progress: summary.totalBudget > 0 ? min(summary.totalCosts / summary.totalBudget, 1.0) : 0.0,
                totalBudget: summary.totalBudget,
                totalCosts: summary.totalCosts
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
            formatter.dateFormat = "yyyy-MM-dd"
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
                    print("✅ Financial goal added with progress: \(newTaskItem.progress ?? 0.0)")
                }

            }.resume()
        }
    }


    
    private func fetchFinancialSummary(completion: @escaping (FinancialSummary?) -> Void) {
        guard username != "Guest",
              let url = URL(string: "http://localhost:8080/api/goals/\(username)/financial-data") else {
            print("⚠️ Invalid username or URL")
            completion(nil)
            return
        }

        print("📡 Fetching financial summary from: \(url)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }

            guard let data = data else {
                print("⚠️ No data received from backend")
                completion(nil)
                return
            }

            do {
                let jsonString = String(data: data, encoding: .utf8)
                print("📜 Raw Financial JSON Response: \(jsonString ?? "No Data")")

                let decodedResponse = try JSONDecoder().decode(FinancialSummary.self, from: data)
                completion(decodedResponse)
            } catch {
                print("❌ Error decoding financial summary JSON: \(error)")
                completion(nil)
            }

        }.resume()
    }

    private func updateFinancialGoalProgress() {
        fetchFinancialSummary { summary in
            guard let summary = summary else {
                print("❌ Failed to fetch financial summary")
                return
            }

            DispatchQueue.main.async {
                // Skip adding if user deleted it
                if self.isFinancialGoalDeleted {
                    print("⚠️ Skipping financial goal because it was deleted")
                    return
                }

                // Remove old financial goals (if any)
                self.tasks.removeAll { $0.isFinancialGoal || $0.name == "Save for Weekly Expenses" }

                // Add fresh updated one
                let updatedFinancialGoal = TaskItem(
                    id: Int.random(in: 1000...9999),
                    name: "Save for Weekly Expenses",
                    isCompleted: false,
                    priority: .medium,
                    isEditing: false,
                    dueDate: nil,
                    notificationsEnabled: false,
                    notificationType: nil,
                    notificationTime: nil,
                    isFinancialGoal: true,
                    progress: summary.totalBudget > 0 ? min(summary.totalCosts / summary.totalBudget, 1.0) : 0.0,
                    totalBudget: summary.totalBudget,
                    totalCosts: summary.totalCosts
                )

                self.tasks.append(updatedFinancialGoal)
                print("✅ Inserted fresh financial goal with progress \(updatedFinancialGoal.progress ?? 0.0)")
            }

        }
    }




    
}


//#Preview {
//    WeeklyGoalsView(
//        tasks: .constant([]),
//        newTask: .constant(""),
//        newTaskPriority: .constant(.medium),
//        newTaskDueDate: .constant(Date()),
//        selectedPriorityFilter: .constant(nil),
//        notificationsEnabled: .constant(false),
//        notificationType: .constant("dueDate"),
//        notificationTime: .constant(Date()),
//        username: "PreviewUser",
//        calendarVM: CalendarViewModel(),
//        fetchGoals: {}
//    )
//}



