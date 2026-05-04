//
//  ContentView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/4/25.
//

import SwiftUI
import Charts

// MARK: - Local tokens (scoped to this file)
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let success        = Color.green
    static let warning        = Color.orange
    static let danger         = Color.red
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius { static let md: CGFloat = 12 }

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

// MARK: - Root
struct ContentView: View {
    @EnvironmentObject var session: AuthViewModel
    @EnvironmentObject var calendarVM: CalendarViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel
    @EnvironmentObject var chatVM: ChatViewModel

    var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest" }

    @State private var isProfilePresented = false
    @State private var isFriendsPresented = false
    @State private var navigateToCalendar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PLSpacing.lg) {
                    // Logo
                    Image("PlotLineLogo")
                        .resizable().scaledToFit()
                        .frame(width: 88, height: 88)
                        .padding(.top, PLSpacing.lg)

                    // Widgets
                    VStack(spacing: PLSpacing.lg) {
                        CalendarWidget()
                            .environmentObject(calendarVM)
                            .environmentObject(friendsVM)
                            .plCard()

                        NavigationLink { BudgetView().environmentObject(calendarVM) } label: {
                            SpendingPreviewWidget() // line chart (current week)
                                .plCard()
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink { NutritionView() } label: {
                            NutritionWidget().plCard()
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink { TopGroceryListView() } label: {
                            GroceryListWidget().plCard()
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink { GoalsView().environmentObject(calendarVM) } label: {
                            GoalsWidget().environmentObject(calendarVM).plCard()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, PLSpacing.lg)
                    .padding(.bottom, PLSpacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("My Dashboard").font(.headline)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { isFriendsPresented = true } label: {
                        Image(systemName: "person.2.fill").font(.title3).foregroundColor(PLColor.accent)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isProfilePresented = true } label: {
                        Image(systemName: "person.circle.fill").font(.title3).foregroundColor(PLColor.accent)
                    }
                }
            }
            .sheet(isPresented: $isProfilePresented) { ProfileView().environmentObject(session) }
            .sheet(isPresented: $isFriendsPresented) {
                SocialTabView()
                    .environmentObject(friendsVM)
                    .environmentObject(chatVM)
            }
            .background(
                NavigationLink(
                    destination: CalendarView()
                        .environmentObject(calendarVM)
                        .environmentObject(friendsVM),
                    isActive: $navigateToCalendar
                ) {
                    EmptyView()
                }
                .hidden()
            )
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToCalendar"))) { notification in
                if let userInfo = notification.userInfo,
                   let showDayView = userInfo["showDayView"] as? Bool,
                   let eventDateStr = userInfo["eventDate"] as? String,
                   let eventDate = ISO8601DateFormatter().date(from: eventDateStr) {

                    // Set the calendar to show the event's date
                    calendarVM.currentDate = eventDate
                    calendarVM.selectedDay = eventDate

                    // Show week view if 24+ hours, otherwise show month view and navigate to day
                    if showDayView {
                        calendarVM.showMonthView()
                        // Navigate to the specific day's event page
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            calendarVM.navigateToDayView = eventDate
                        }
                    } else {
                        calendarVM.showWeekView()
                    }
                }
                navigateToCalendar = true
            }
        }
        .task {
            calendarVM.fetchEvents()
            await friendsVM.loadFriends(for: username)
        }
        .onAppear {
            // Handle pending notification navigation from cold start
            if let userInfo = AppDelegate.pendingNotificationUserInfo {
                AppDelegate.pendingNotificationUserInfo = nil // Clear it

                if let showDayView = userInfo["showDayView"] as? Bool,
                   let eventDateStr = userInfo["eventDate"] as? String,
                   let eventDate = ISO8601DateFormatter().date(from: eventDateStr) {

                    // Set the calendar to show the event's date
                    calendarVM.currentDate = eventDate
                    calendarVM.selectedDay = eventDate

                    // Show week view if 24+ hours, otherwise show month view and navigate to day
                    if showDayView {
                        calendarVM.showMonthView()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            calendarVM.navigateToDayView = eventDate
                        }
                    } else {
                        calendarVM.showWeekView()
                    }

                    navigateToCalendar = true
                }
            }
        }
    }
}

// MARK: - Calendar Widget
struct CalendarWidget: View {
    @EnvironmentObject var viewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel

    var body: some View {
        NavigationLink {
            CalendarView()
                .environmentObject(viewModel)
                .environmentObject(friendVM)
        } label: {
            VStack(alignment: .leading, spacing: PLSpacing.sm) {
                HStack {
                    Label("Today's Events", systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                    Spacer()
                }

                let todayEvents = viewModel.eventsOnDay(Date())

                if todayEvents.isEmpty {
                    Text("Nothing on the books today.")
                        .foregroundColor(PLColor.textSecondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(todayEvents) { event in
                            HStack(spacing: 8) {
                                Circle().frame(width: 6, height: 6).foregroundColor(PLColor.accent)
                                Text(event.title).font(.body).lineLimit(1)
                                Spacer()
                                if event.eventType == "rent" {
                                    Badge(text: "Due Today", color: PLColor.danger)
                                } else if event.eventType.lowercased().hasPrefix("subscription") {
                                    Badge(text: "Billed", color: PLColor.warning)
                                } else if event.startDate != event.endDate {
                                    Text("Thru \(formattedEndDate(event.endDate))")
                                        .font(.caption).foregroundColor(PLColor.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formattedEndDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }

    private struct Badge: View {
        let text: String; let color: Color
        var body: some View {
            Text(text)
                .font(.caption).foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25)))
        }
    }
}

// MARK: - Spending Preview (Line/Area chart for current week)
struct SpendingPreviewWidget: View {
    @State private var points: [DayPoint] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var reloadTrigger = UUID()

    private var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weekly Spending (Sun–Sat)", systemImage: "chart.line.uptrend.xyaxis")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                Spacer()
            }

            if isLoading && points.isEmpty {
                HStack(spacing: 8) { ProgressView(); Text("Loading…").foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let errorText, points.isEmpty {
                Text(errorText).foregroundColor(.red).font(.footnote)
            } else {
                Chart {
                    // Area
                    ForEach(points) { p in
                        AreaMark(
                            x: .value("Day", p.date),
                            y: .value("Spent", p.total)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.blue.opacity(0.18))
                    }
                    // Line
                    ForEach(points) { p in
                        LineMark(
                            x: .value("Day", p.date),
                            y: .value("Spent", p.total)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(.blue)
                    }
                    // Points
                    ForEach(points) { p in
                        PointMark(
                            x: .value("Day", p.date),
                            y: .value("Spent", p.total)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: points.map(\.date)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.weekday(.narrow))
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
                .animation(.easeInOut, value: points.count)   // <— no Equatable requirement
            }
        }
        .task(id: reloadTrigger) { await reloadWeek() }
        .onReceive(NotificationCenter.default.publisher(for: .plaidSynced)) { _ in
            reloadTrigger = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            reloadTrigger = UUID()
        }
    }

    private func reloadWeek() async {
        await MainActor.run { isLoading = true; errorText = nil }
        do {
            let series = try await fetchCurrentWeekSeries()
            await MainActor.run {
                self.points = series
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorText = "Couldn’t load weekly spending."
                self.points = []
                self.isLoading = false
            }
        }
    }

    // Derive current week's daily spending from the monthly file
    private func fetchCurrentWeekSeries() async throws -> [DayPoint] {
        let cal = Calendar.current
        let weekStart = cal.startOfWeek(for: Date())
        let f = DateFormatter(); f.calendar = .init(identifier: .gregorian); f.dateFormat = "yyyy-MM"
        let monthStr = f.string(from: Date())

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/costs/monthly/\(username)?month=\(monthStr)") else {
            return []
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Period: Decodable { let days: [String:[String:Double]]? }
        let period = try JSONDecoder().decode(Period.self, from: data)

        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let dayMap = period.days ?? [:]

        return days.map { d in
            let key = d.ymd()
            let total = (dayMap[key] ?? [:]).values.reduce(0, +)
            return DayPoint(date: d, total: total)
        }
    }

    private struct DayPoint: Identifiable {
        let id = UUID()
        let date: Date
        let total: Double
    }
}


// MARK: - Goals Widget (same data, modern card)
struct GoalsWidget: View {
    @EnvironmentObject var calendarVM: CalendarViewModel
    @State private var tasks: [TaskItem] = []
    @State private var isLoading = true
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"

    var body: some View {
        NavigationLink { GoalsView().environmentObject(calendarVM) } label: {
            VStack(alignment: .leading, spacing: PLSpacing.sm) {
                HStack {
                    Label("Goals", systemImage: "list.bullet.rectangle.portrait")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                    Spacer()
                }

                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 6)
                } else if tasks.isEmpty {
                    Text("No goals yet")
                        .foregroundColor(PLColor.textSecondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(tasks.prefix(3)), id: \.id) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.body)
                                Text("Due: \(formatDate(t.dueDate))")
                                    .font(.caption).foregroundColor(PLColor.textSecondary)
                            }
                        }
                        if tasks.count > 3 {
                            Text("+ \(tasks.count - 3) more")
                                .font(.caption).foregroundColor(PLColor.textSecondary)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .task { await fetchGoals() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await fetchGoals() }
        }
    }

    private func formatDate(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
    }

    private func fetchGoals() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)") else { return }
        var request = URLRequest(url: url); request.httpMethod = "GET"
        BackendConfig.addApiKey(to: &request)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            decoder.dateDecodingStrategy = .formatted(fmt)

            // response shape: { "weeklyGoals": [...] }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = root["weeklyGoals"],
               let arrData = try? JSONSerialization.data(withJSONObject: arr) {
                let decoded = try decoder.decode([TaskItem].self, from: arrData)
                await MainActor.run { self.tasks = decoded; self.isLoading = false }
            } else {
                await MainActor.run { self.tasks = []; self.isLoading = false }
            }
        } catch {
            await MainActor.run { self.tasks = []; self.isLoading = false }
        }
    }
}

// MARK: - Grocery Widget (styling only)
struct GroceryListWidget: View {
    @State private var groceryLists: [GroceryList] = []
    @State private var isLoading = false
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Label("Meals & Grocery", systemImage: "fork.knife")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                Spacer()
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 6)
            } else if groceryLists.isEmpty {
                Text("No active grocery lists")
                    .foregroundColor(PLColor.textSecondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(groceryLists.prefix(3).enumerated()), id: \.element.id) { _, list in
                        HStack {
                            Circle().frame(width: 6, height: 6).foregroundColor(PLColor.success)
                            Text(list.name).font(.body)
                            Spacer()
                        }
                    }
                    if groceryLists.count > 3 {
                        Text("+ \(groceryLists.count - 3) more")
                            .font(.caption).foregroundColor(PLColor.textSecondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .task { await fetchGroceryLists() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await fetchGroceryLists() }
        }
    }

    private func fetchGroceryLists() async {
        await MainActor.run { isLoading = true }
        do {
            let lists = try await GroceryListAPI.getGroceryLists(username: username)
            await MainActor.run { self.groceryLists = lists; self.isLoading = false }
        } catch {
            await MainActor.run { self.isLoading = false }
        }
    }
}

// MARK: - Nutrition Widget
struct NutritionWidget: View {
    @State private var todayEntry: NutritionEntry?
    @State private var userData: NutritionUserData?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            HStack {
                Label("Nutrition", systemImage: "leaf.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                Spacer()
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 6)
            } else if let entry = todayEntry, !entry.foods.isEmpty {
                if let goal = userData?.goals, goal.calorieGoal > 0 {
                    // Goal-aware display
                    let remaining = max(0, goal.calorieGoal - entry.totalCalories)
                    let progress = min(entry.totalCalories / goal.calorieGoal, 1.0)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.15), lineWidth: 6)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(entry.totalCalories > goal.calorieGoal ? Color.red : Color.blue,
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(remaining))")
                                .font(.system(.caption, design: .rounded).bold())
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(remaining)) cal remaining")
                                .font(.subheadline.bold())
                            Text("\(Int(entry.totalCalories)) / \(Int(goal.calorieGoal)) cal")
                                .font(.caption).foregroundColor(PLColor.textSecondary)
                        }
                        Spacer()
                    }
                } else {
                    // No goal
                    HStack(spacing: PLSpacing.lg) {
                        VStack {
                            Text("\(Int(entry.totalCalories))")
                                .font(.system(.title2, design: .rounded).bold())
                                .foregroundColor(PLColor.accent)
                            Text("cal").font(.caption).foregroundColor(PLColor.textSecondary)
                        }
                        Spacer()
                        VStack {
                            Text("\(Int(entry.totalProtein))g").font(.subheadline.bold())
                            Text("Protein").font(.caption2).foregroundColor(PLColor.textSecondary)
                        }
                        VStack {
                            Text("\(Int(entry.totalCarbs))g").font(.subheadline.bold())
                            Text("Carbs").font(.caption2).foregroundColor(PLColor.textSecondary)
                        }
                        VStack {
                            Text("\(Int(entry.totalFat))g").font(.subheadline.bold())
                            Text("Fat").font(.caption2).foregroundColor(PLColor.textSecondary)
                        }
                    }
                }
                Text("\(entry.foods.count) food\(entry.foods.count == 1 ? "" : "s") logged today")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            } else {
                Text("No foods logged today")
                    .foregroundColor(PLColor.textSecondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .task { await reloadNutrition() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await reloadNutrition() }
        }
    }

    private func reloadNutrition() async {
        await MainActor.run { isLoading = true }
        async let entryTask = NutritionAPI.shared.fetchEntries(for: Date())
        async let userDataTask = NutritionAPI.shared.fetchUserData()
        let entry = try? await entryTask
        let data = try? await userDataTask
        await MainActor.run {
            todayEntry = entry
            userData = data
            isLoading = false
        }
    }
}

// MARK: - Small utilities

private extension Date {
    func asWeekdayShort() -> String {
        let f = DateFormatter(); f.dateFormat = "E"; return f.string(from: self)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(CalendarViewModel())
        .environmentObject(FriendsViewModel())
        .environmentObject(ChatViewModel())
}
