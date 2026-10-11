import SwiftUI

struct GoalsView: View {
    @State private var selectedView: GoalViewType = .weekly
    @State private var tasks: [TaskItem] = []
    @State private var longTermGoals: [LongTermGoal] = []

    @State private var selectedPriorityFilter: Priority? = nil

    @EnvironmentObject var calendarVM: CalendarViewModel
    @ObservedObject private var router = GoalsRouter.shared

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
                    longTermGoals: $longTermGoals,
                    selectedPriorityFilter: $selectedPriorityFilter,
                    username: username,
                    calendarVM: calendarVM
                )
            } else {
                LongTermGoalsView(
                    longTermGoals: $longTermGoals,
                    weeklyGoals: $tasks,
                    username: username,
                    calendarVM: calendarVM
                )
            }
        }
        .navigationTitle("Goals")
        .onAppear {
            fetchGoals()
            fetchLongTermGoals()
            if let tab = router.request?.tab { selectedView = tab }
        }
        // a tapped reminder: switch to its tab (the tab then opens the goal)
        .onChange(of: router.request) { _, request in
            if let tab = request?.tab { selectedView = tab }
        }
    }

    // MARK: - Logic (unchanged)

    private func fetchGoals() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)") else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if AppBanner.reportIfFailed("load your goals", data, response, error, retry: { fetchGoals() }) { return }
            guard let data = data else { return }
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
                    // e.g. on a new phone: put this account's saved reminders back on it
                    GoalReminders.sync(decodedResponse.weeklyGoals)
                }
            } catch {
                AppBanner.report("load your goals", error, retry: { fetchGoals() })
            }
        }.resume()
    }

    private func fetchLongTermGoals() {
        guard username != "Guest",
              let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term") else { return }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if AppBanner.reportIfFailed("load your long-term goals", data, response, error, retry: { fetchLongTermGoals() }) { return }
            guard let data = data else { return }
            do {
                let decodedResponse = try JSONDecoder().decode(LongTermGoalsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.longTermGoals = decodedResponse.longTermGoals
                    GoalReminders.syncLongTerm(decodedResponse.longTermGoals) // e.g. on a new phone
                }
            } catch {
                AppBanner.report("load your long-term goals", error, retry: { fetchLongTermGoals() })
            }
        }.resume()
    }
}
