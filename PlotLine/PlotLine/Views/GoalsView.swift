import SwiftUI

private enum PLSpacing {
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}

struct GoalsView: View {
    @State private var selectedView: GoalViewType = .weekly
    @State private var tasks: [TaskItem] = []
    @State private var longTermGoals: [LongTermGoal] = []

    @State private var newTask: String = ""
    @State private var newTaskPriority: Priority = .medium
    @State private var newTaskDueDate = Date()
    @State private var selectedPriorityFilter: Priority? = nil
    @State private var notificationsEnabled = false
    @State private var notificationType: String = "dueDate"
    @State private var notificationTime: Date = Date()

    @State private var newLongTermTitle: String = ""
    @State private var newStep: String = ""
    @State private var newLongTermSteps: [String] = []

    @EnvironmentObject var calendarVM: CalendarViewModel

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedView) {
                Text("Weekly").tag(GoalViewType.weekly)
                Text("Long Term").tag(GoalViewType.longTerm)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.md)

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
        .navigationTitle("Goals")
        .onAppear {
            fetchGoals()
            fetchLongTermGoals()
        }
    }

    // MARK: - Logic (unchanged)

    private func fetchGoals() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)") else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("❌ Network error: \(error.localizedDescription)"); return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data else { return }
            do {
                let decoder = JSONDecoder()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                decoder.dateDecodingStrategy = .formatted(formatter)
                let decodedResponse = try decoder.decode(GoalsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.tasks = decodedResponse.weeklyGoals
                    WidgetDataWriter.writeGoals(decodedResponse.weeklyGoals)
                    WidgetDataWriter.reloadWidgets()
                }
            } catch {
                print("❌ Error decoding JSON: \(error)")
            }
        }.resume()
    }

    private func fetchLongTermGoals() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term") else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("❌ Network error: \(error.localizedDescription)"); return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data else { return }
            do {
                let decodedResponse = try JSONDecoder().decode(LongTermGoalsResponse.self, from: data)
                DispatchQueue.main.async { self.longTermGoals = decodedResponse.longTermGoals }
            } catch {
                print("❌ Error decoding long-term goals JSON: \(error)")
            }
        }.resume()
    }
}
