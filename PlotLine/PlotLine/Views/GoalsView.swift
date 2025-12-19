import SwiftUI

struct GoalsView: View {
    @State private var selectedView: GoalViewType = .weekly
    @State private var tasks: [TaskItem] = []
    @State private var longTermGoals: [LongTermGoal] = []

    // Weekly goals state variables
    @State private var newTask: String = ""
    @State private var newTaskPriority: Priority = .medium
    @State private var newTaskDueDate = Date()
    @State private var selectedPriorityFilter: Priority? = nil
    @State private var notificationsEnabled = false
    @State private var notificationType: String = "dueDate"
    @State private var notificationTime: Date = Date()

    // Long term goals state variables
    @State private var newLongTermTitle: String = ""
    @State private var newStep: String = ""
    @State private var newLongTermSteps: [String] = []

    @EnvironmentObject var calendarVM: CalendarViewModel
    
    /* Fetch the logged-in username from UserDefaults */
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }
    
    var body: some View {
        VStack {
            // Toggle buttons (keep this part)
            HStack {
                Button(action: { selectedView = .weekly }) {
                    Text("Weekly")
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(selectedView == .weekly ? Color.gray.opacity(0.8) : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                Button(action: { selectedView = .longTerm }) {
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
                WeeklyGoalsView(
                    tasks: $tasks,
                    newTask: $newTask,
                    newTaskPriority: $newTaskPriority,
                    newTaskDueDate: $newTaskDueDate,
                    selectedPriorityFilter: $selectedPriorityFilter,
                    notificationsEnabled: $notificationsEnabled,
                    notificationType: $notificationType,
                    notificationTime: $notificationTime,
                    username: username,
                    calendarVM: calendarVM,
                    fetchGoals: fetchGoals
                )
            } else {
                LongTermGoalsView(
                    longTermGoals: $longTermGoals,
                    newLongTermTitle: $newLongTermTitle,
                    newStep: $newStep,
                    newLongTermSteps: $newLongTermSteps,
                    username: username
                )
            }
        }
        .onAppear {
            fetchGoals()
            fetchLongTermGoals()
        }
    }
    
    
    /* Fetch Weekly Goals */
    private func fetchGoals() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)") else {
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
    
    /* Fetch Long term goals */
    private func fetchLongTermGoals() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term") else {
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
    
    
    
}
