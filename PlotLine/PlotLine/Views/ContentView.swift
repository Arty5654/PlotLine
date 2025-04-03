//
//  ContentView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/4/25.
//

import SwiftUI
import Charts

struct ContentView: View {
    
    @EnvironmentObject var session: AuthViewModel
    @EnvironmentObject var calendarVM: CalendarViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel
    
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    @State private var isProfilePresented = false
    @State private var isFriendsPresented = false

    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack() {
                    
                    //logo
                    logoImage
                        .padding(.bottom, 20)
                    Spacer()
                    
                    // widgets
                    VStack(spacing: 25) {
                        
                        // Today's Events Widget
                        CalendarWidget()
                            .environmentObject(calendarVM)
                            .padding(.horizontal)
                        
                        // Budget Preview Widget
                        NavigationLink(destination: BudgetView().environmentObject(calendarVM)) {
                            SpendingPreviewWidget()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                        
                        
//                        NavigationLink(destination: BudgetView().environmentObject(calendarVM)) {
//                            Label("Budget", systemImage: "creditcard.fill")
//                                .font(.headline)
//                                .padding()
//                                .frame(maxWidth: .infinity)
//                                .background(Color.green)
//                                .cornerRadius(8)
//                                .foregroundColor(.white)
//                        }

                        // In your ContentView's VStack where other widgets are
                        NavigationLink(destination: TopGroceryListView()) {
                            GroceryListWidget()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)

                        NavigationLink(destination: WeeklyGoalsView()) {
                            Label("Goals", systemImage: "list.bullet.rectangle.fill")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        
                        NavigationLink(destination: HealthView()) {
                            HealthWidget()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                    }
                    .padding([.horizontal, .bottom])
                    
                }
                .padding()
            }
            .ignoresSafeArea(edges: .bottom)
            
            .navigationBarItems(
                leading: friendPageButton,
                trailing: profileButton
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("My Dashboard")
            .sheet(isPresented: $isProfilePresented) {
                ProfileView().environmentObject(session)
            }
            .sheet(isPresented: $isFriendsPresented) {
                FriendsView().environmentObject(friendsVM)
            }
        }
        .task {
            calendarVM.fetchEvents()
        }
    }
    
    private var profileButton: some View {
            Button(action: {
                isProfilePresented = true
            }) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.blue)
            }
        }
    
    private var friendPageButton: some View {
        Button(action: {
            isFriendsPresented = true
        }) {
            Image(systemName: "person.2.fill")
                .resizable()
                .foregroundColor(.blue)
        }
    }

    
    private var logoImage: some View {
        Image("PlotLineLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
    }
}


struct CalendarWidget: View {
    
    @EnvironmentObject var viewModel: CalendarViewModel

    var body: some View {
        NavigationLink(destination: CalendarView().environmentObject(viewModel)) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Text("Today's Events")
                        .font(.custom("AvenirNext-Bold", size: 18))
                        .foregroundColor(.blue)
                                    
                    HStack {
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                }
                                .padding(.horizontal)
                let todayEvents = viewModel.eventsOnDay(Date())

                if todayEvents.isEmpty {
                    Text("No events today")
                        .foregroundColor(.gray)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(todayEvents) { event in
                            HStack {
                                // Bullet point and event title
                                Text("• \(event.title)")
                                    .font(.body)
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if (event.eventType == "rent") {
                                    
                                    Text("Due Today!")
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                        .frame(alignment: .trailing)
                                    
                                } else if (event.eventType.lowercased().starts(with: "subscription")) {
                                    Text("Billed Today!")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                        .frame(alignment: .trailing)
                                } else if (event.startDate != event.endDate) {
                                    Text("Through \(formattedEndDate(event.endDate))")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .frame(alignment: .trailing)
                                }
                                
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formattedEndDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }
}

struct SpendingPreviewWidget: View {
    @State private var spendingData: [SpendingEntry] = []
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly Spending Preview")
                .font(.headline)
            
            Chart {
                ForEach(spendingData, id: \.category) { entry in
                    BarMark(
                        x: .value("Category", entry.category),
                        y: .value("Amount", entry.amount)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .frame(height: 120)
            .onAppear {
                fetchSpendingData()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    private func fetchSpendingData() {
        guard let url = URL(string: "http://localhost:8080/api/costs/\(username)/weekly") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else { return }
            
            DispatchQueue.main.async {
                self.spendingData = decoded.costs.map { SpendingEntry(category: $0.key, amount: $0.value) }
            }
        }.resume()
    }
}

struct HealthWidget: View {
    @State private var sleepData: SleepEntry?
    @State private var sleepSchedule: SleepSchedule?
    @State private var isLoading = true
    @State private var error: String?
    
    private let healthAPI = HealthAPI()
    private let sleepAPI = SleepAPI()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            ZStack {
                Text("Health")
                    .font(.custom("AvenirNext-Bold", size: 18))
                    .foregroundColor(.blue)
                            
                HStack {
                    Spacer()
                    Image(systemName: "heart.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let error = error {
                Text(error)
                    .foregroundColor(.gray)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else if let sleepData = sleepData, let schedule = sleepSchedule {
                VStack(spacing: 12) {
                    // Last night's sleep summary
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Last night")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text("\(sleepData.hoursSlept) hours")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(sleepQualityColor(sleepData.hoursSlept, targetHours: calculateTargetSleepHours(wakeUpTime: schedule.wakeUpTime, sleepTime: schedule.sleepTime)))
                        }
                        
                        Spacer()
                        
                        // Mood indicator
                        VStack(alignment: .trailing) {
                            Text("Mood")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text(moodEmoji(sleepData.mood))
                                .font(.system(size: 24))
                        }
                    }
                    
                    Divider()
                    
                    // Tonight's sleep schedule
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Tonight")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text(formatTime(schedule.sleepTime))
                                .font(.headline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Wake up")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text(formatTime(schedule.wakeUpTime))
                                .font(.headline)
                        }
                    }
                    
                    // Bedtime reminder
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                        
                        Text("Reminder at \(formatTime(calculateReminderTime(from: schedule.sleepTime)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            } else {
                Text("No sleep data available")
                    .foregroundColor(.gray)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        .onAppear {
            loadSleepData()
        }
    }
    
    private func loadSleepData() {
        isLoading = true
        error = nil
        
        Task {
            do {
                // Get today's date at midnight
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                
                // Get yesterday's date
                guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                    throw NSError(domain: "HealthWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not calculate yesterday's date"])
                }
                
                // Fetch entries for the last week
                let entries = try await healthAPI.fetchEntriesForWeek(containing: yesterday)
                
                // Find yesterday's entry
                let yesterdayEntry = entries.first { entry in
                    calendar.isDate(entry.date, inSameDayAs: yesterday)
                }
                
                // Fetch sleep schedule
                let schedule = try await sleepAPI.fetchSleepSchedule()
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.sleepData = yesterdayEntry.map { SleepEntry(hoursSlept: $0.hoursSlept, mood: $0.mood) }
                    self.sleepSchedule = schedule
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Could not load sleep data"
                    self.isLoading = false
                    print("Error loading sleep data: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Helper functions
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func calculateReminderTime(from sleepTime: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .hour, value: -1, to: sleepTime) ?? sleepTime
    }
    
    private func moodEmoji(_ mood: String) -> String {
        switch mood.lowercased() {
        case "bad":
            return "😞"
        case "okay":
            return "😐"
        case "good":
            return "😊"
        default:
            return "❓"
        }
    }
    
    private func sleepQualityColor(_ hours: Int, targetHours: Double) -> Color {
        if Double(hours) >= targetHours {
            return .green
        } else if Double(hours) >= targetHours * 0.8 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func calculateTargetSleepHours(wakeUpTime: Date, sleepTime: Date) -> Double {
        let calendar = Calendar.current
        
        // Convert to minutes for easier calculation
        let sleepComponents = calendar.dateComponents([.hour, .minute], from: sleepTime)
        let wakeComponents = calendar.dateComponents([.hour, .minute], from: wakeUpTime)
        
        let sleepMinutes = (sleepComponents.hour ?? 0) * 60 + (sleepComponents.minute ?? 0)
        let wakeMinutes = (wakeComponents.hour ?? 0) * 60 + (wakeComponents.minute ?? 0)
        
        // If sleep time is after wake time, it means sleep spans across midnight
        let totalMinutes = sleepMinutes > wakeMinutes
            ? (24 * 60 - sleepMinutes) + wakeMinutes
            : wakeMinutes - sleepMinutes
            
        // Convert back to hours (with fraction)
        return Double(totalMinutes) / 60.0
    }
}

// Simple data structure for sleep entry display
struct SleepEntry {
    let hoursSlept: Int
    let mood: String
}

struct GroceryListWidget: View {
    @State private var groceryLists: [GroceryList] = []
    @State private var isLoading: Bool = false
    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            ZStack {
                Text("Grocery Lists")
                    .font(.custom("AvenirNext-Bold", size: 18))
                    .foregroundColor(.blue)
                            
                HStack {
                    Spacer()
                    Image(systemName: "cart.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 10)
            } else if groceryLists.isEmpty {
                Text("No active grocery lists")
                    .foregroundColor(.gray)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    // Display up to 3 lists
                    ForEach(Array(groceryLists.prefix(3).enumerated()), id: \.element.id) { index, list in
                        HStack {
                            Text("• \(list.name)")
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // Show total count if more than 3 lists
                    if groceryLists.count > 3 {
                        Text("+ \(groceryLists.count - 3) more lists")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        .onAppear {
            fetchGroceryLists()
        }
    }
    
    private func fetchGroceryLists() {
        isLoading = true
        
        Task {
            do {
                let lists = try await GroceryListAPI.getGroceryLists(username: username)
                DispatchQueue.main.async {
                    self.groceryLists = lists
                    self.isLoading = false
                }
            } catch {
                print("Failed to load grocery lists: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(CalendarViewModel())
}
