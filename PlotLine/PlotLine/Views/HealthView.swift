//
//  HealthView.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/2/25.
//

import SwiftUI
import UserNotifications

func setupNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if granted {
            print("Notification permission granted")
        } else if let error = error {
            print("Notification permission error: \(error.localizedDescription)")
        }
    }
}

struct HealthView: View {
    // Date selection
    @State private var logDate = Date()
    @State private var currentWeekSunday: Date = {
        let calendar = Calendar.current
        let today = Date()
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
    }()
    
    // Form values
    @State private var hoursSlept: Int = 8
    @State private var mood: String = ""
    @State private var notes: String = ""
    
    @State private var sleepSchedule: SleepSchedule?
    @State private var targetHours: Double = 9.0
    
    @State private var showingSleepSchedule = false
    
    @State private var weekEntries: [HealthEntry] = []
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    private let healthAPI = HealthAPI()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Custom Date Picker
            DateRowPicker(
                selectedDate: $logDate,
                onDateSelected: dateSelected
            )
            
            VStack(spacing: 16) {
                let targetHours = calculateTargetSleepHours(
                    wakeUpTime: sleepSchedule?.wakeUpTime ?? Date(),
                    sleepTime: sleepSchedule?.sleepTime ?? Date()
                )
                
                HStack {
                    Text("Hours Slept:")
                    Spacer()
                    Text("\(hoursSlept)")
                        .frame(minWidth: 20, alignment: .trailing)
                    Stepper("", value: $hoursSlept, in: 0...24)
                        .labelsHidden()
                }
                
                HStack(alignment: .center, spacing: 12) {
                    Text("Mood:")
                        .font(.body)
                        .frame(width: 60, alignment: .leading)

                    HStack(spacing: 12) {
                        MoodButton(value: "Bad", selectedMood: $mood)
                        MoodButton(value: "Okay", selectedMood: $mood)
                        MoodButton(value: "Good", selectedMood: $mood)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(
                sleepQualityColor(hoursSlept)
            )
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Notes Section
            VStack(alignment: .leading) {
                Text("Notes")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                TextEditor(text: $notes)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
            }

            Spacer()

            // Save Button
            Button(action: {
                Task {
                    await saveHealthEntry()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Save")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Sleep Schedule Button
            Button(action: {
                showingSleepSchedule = true
            }) {
                Text("View Sleep Schedule")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.primary)
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
        .onAppear {
            Task {
                await loadCurrentWeekData()
                await loadSleepSchedule()
                setupNotifications()
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingSleepSchedule) {
            SleepScheduleView()
        }
    }
    
    // Helper function to show whether enough sleep was logged
    private func sleepQualityColor(_ hours: Int) -> Color {
        let target = calculateTargetSleepHours(
            wakeUpTime: sleepSchedule?.wakeUpTime ?? Date(),
            sleepTime: sleepSchedule?.sleepTime ?? Date()
        )
        
        return hours >= Int(target) ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
    }
    
    // MARK: - Notification Functions
    
    private func scheduleBedtimeReminder() {
        guard let sleepSchedule = self.sleepSchedule else { return }
        
        // Remove any existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        let sleepTime = sleepSchedule.sleepTime
        let calendar = Calendar.current
        
        var reminderComponents = calendar.dateComponents([.hour, .minute], from: sleepTime)

        if let hour = reminderComponents.hour {
            reminderComponents.hour = hour - 1
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Time to Wind Down"
        content.body = "Your bedtime is in 1 hour. Start preparing for sleep!"
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "bedtimeReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Data Loading Functions
    
    private func loadCurrentWeekData() async {
        isLoading = true
        
        do {
            let entries = try await healthAPI.fetchEntriesForWeek(containing: currentWeekSunday)
            weekEntries = entries
            dateSelected(logDate)
            isLoading = false
        } catch URLError.userAuthenticationRequired {
            isLoading = false
            showError("Not Logged In", "Please log in to view your health data.")
        } catch {
            isLoading = false
            showError("Failed to Load Data", error.localizedDescription)
        }
    }
    
    private func loadSleepSchedule() async {
         let sleepAPI = SleepAPI()
         do {
             sleepSchedule = try await sleepAPI.fetchSleepSchedule()
             // Schedule notification after loading sleep schedule
             scheduleBedtimeReminder()
         } catch {
             // Handle error or use default schedule
             let calendar = Calendar.current
             var wakeComponents = calendar.dateComponents([.year, .month, .day], from: Date())
             wakeComponents.hour = 9
             wakeComponents.minute = 0
             let wakeUpTime = calendar.date(from: wakeComponents) ?? Date()
             
             var sleepComponents = calendar.dateComponents([.year, .month, .day], from: Date())
             sleepComponents.hour = 23
             sleepComponents.minute = 0
             let sleepTime = calendar.date(from: sleepComponents) ?? Date()
             
             sleepSchedule = SleepSchedule(wakeUpTime: wakeUpTime, sleepTime: sleepTime)
             // Schedule notification with default schedule
             scheduleBedtimeReminder()
         }
     }
    
    private func dateSelected(_ date: Date) {
        // Check if we have an entry for this date
        let calendar = Calendar.current
        if let entry = weekEntries.first(where: { entry in
            let entryComponents = calendar.dateComponents([.year, .month, .day], from: entry.date)
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
            return entryComponents.year == dateComponents.year &&
                   entryComponents.month == dateComponents.month &&
                   entryComponents.day == dateComponents.day
        }) {
            // Load the entry data
            loadEntryData(entry)
        } else {
            // Reset the form for a new entry on this date
            resetFormForDate(date)
        }
        
        // Make sure we also have the sleep schedule updated
        if sleepSchedule == nil {
            Task {
                await loadSleepSchedule()
            }
        }
    }
    
    private func loadEntryData(_ entry: HealthEntry) {
        // Load all the entry data into our form
        self.hoursSlept = entry.hoursSlept
        self.mood = entry.mood
        self.notes = entry.notes
    }
    
    private func resetFormForDate(_ date: Date) {
        // Reset fields
        self.hoursSlept = 8
        self.mood = ""
        self.notes = ""
    }
    
    // MARK: - Save Function

    private func saveHealthEntry() async {
        // Validate form
        if mood.isEmpty {
            showError("Missing Information", "Please select a mood before saving.")
            return
        }
        
        isLoading = true
        
        // First get the sleep schedule to use those times
        let sleepAPI = SleepAPI()
        var sleepSchedule: SleepSchedule
        
        do {
            sleepSchedule = try await sleepAPI.fetchSleepSchedule()
        } catch {
            // If can't fetch schedule, use default times
            let calendar = Calendar.current
            var wakeComponents = calendar.dateComponents([.year, .month, .day], from: logDate)
            wakeComponents.hour = 9
            wakeComponents.minute = 0
            let wakeUpTime = calendar.date(from: wakeComponents) ?? logDate
            
            var sleepComponents = calendar.dateComponents([.year, .month, .day], from: logDate)
            sleepComponents.hour = 23
            sleepComponents.minute = 0
            let sleepTime = calendar.date(from: sleepComponents) ?? logDate
            
            sleepSchedule = SleepSchedule(wakeUpTime: wakeUpTime, sleepTime: sleepTime)
        }
        
        // Set date to noon on the selected day to avoid timezone issues
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: logDate)
        dateComponents.hour = 12
        dateComponents.minute = 0
        dateComponents.second = 0
        let standardizedDate = calendar.date(from: dateComponents)!
        
        // Check if an entry already exists for this date
        let startOfDay = calendar.startOfDay(for: logDate)
        let existingEntry = weekEntries.first(where: { entry in
            let entryStartOfDay = calendar.startOfDay(for: entry.date)
            return calendar.isDate(entryStartOfDay, inSameDayAs: startOfDay)
        })
        
        // Create a health entry from the form data with sleep schedule times
        let entry = HealthEntry(
            id: existingEntry?.id ?? UUID(), // Use existing ID or create new one
            date: standardizedDate,
            wakeUpTime: sleepSchedule.wakeUpTime,
            sleepTime: sleepSchedule.sleepTime,
            hoursSlept: hoursSlept,
            mood: mood,
            notes: notes
        )
        
        do {
            // Save the entry
            try await healthAPI.saveEntry(entry)
                        
            // Update our local week entries array
            if let index = weekEntries.firstIndex(where: { entry in
                let entryStartOfDay = calendar.startOfDay(for: entry.date)
                return calendar.isDate(entryStartOfDay, inSameDayAs: startOfDay)
            }) {
                weekEntries[index] = entry
            } else {
                weekEntries.append(entry)
            }
                        
            // Reschedule notification after saving
            scheduleBedtimeReminder()
            
            isLoading = false
            showSuccess("Entry Saved", "Your health entry was saved successfully.")
        } catch URLError.userAuthenticationRequired {
            isLoading = false
            showError("Not Logged In", "Please log in to save your health data.")
        } catch {
            isLoading = false
            showError("Save Failed", "Could not save your health entry: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Message Helper Functions
    private func showError(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
    
    private func showSuccess(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - MoodButton Component
struct MoodButton: View {
    var value: String
    @Binding var selectedMood: String

    var body: some View {
        Button(action: {
            selectedMood = value
        }) {
            Text(value)
                .font(.body)
                .padding()
                .lineLimit(1)
                .fixedSize()
                .background(selectedMood.lowercased() == value.lowercased() ? Color.blue.opacity(0.2) : Color.clear)
                .cornerRadius(10)
        }
    }
}

// MARK: - DateRowPicker Component
struct DateRowPicker: View {
    @Binding var selectedDate: Date
    @State private var visibleDates: [Date] = []
    @State private var weekOffset: Int = 0
    private let today = Date()
    var onDateSelected: ((Date) -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
            HStack(spacing: 0) {
                ForEach(0..<7) { index in
                    Text(daysOfWeek[index])
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                }
            }
            .padding(.top, 8)
            
            // Date circles row
            HStack(spacing: 0) {
                ForEach(visibleDates, id: \.self) { date in
                    let isSelectable = !date.isAfterDate(today)
                    
                    DateCircle(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        isToday: Calendar.current.isDateInToday(date),
                        isSelectable: isSelectable
                    )
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        if isSelectable {
                            selectedDate = date
                            onDateSelected?(date)
                        }
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width > 50 {
                            // Swipe right - show previous week
                            withAnimation {
                                // Save the weekday component before changing dates
                                let weekdayToPreserve = Calendar.current.component(.weekday, from: selectedDate)
                                
                                weekOffset -= 1
                                updateVisibleDates()
                                
                                // Find the equivalent day in the new week
                                preserveSelectedDayOfWeek(weekday: weekdayToPreserve)
                            }
                        } else if value.translation.width < -50 {
                            // Swipe left - show next week (if not in future)
                            let potentialNewOffset = weekOffset + 1
                            if !isFutureWeek(offset: potentialNewOffset) {
                                withAnimation {
                                    // Save the weekday component before changing dates
                                    let weekdayToPreserve = Calendar.current.component(.weekday, from: selectedDate)
                                    
                                    weekOffset = potentialNewOffset
                                    updateVisibleDates()
                                    
                                    // Find the equivalent day in the new week
                                    preserveSelectedDayOfWeek(weekday: weekdayToPreserve)
                                }
                            }
                        }
                    }
            )
            .padding(.vertical, 10)
            
            // Selected date label
            Text(formattedSelectedDate)
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear {
            updateVisibleDates()
            // Ensure initial selectedDate is not in the future
            if selectedDate.isAfterDate(today) {
                selectedDate = today
            }
        }
    }
    
    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE — MMM d, yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private func updateVisibleDates() {
        let calendar = Calendar.current
        
        // Get the start of the current week (Sunday)
        let startOfWeekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let startOfWeek = calendar.date(from: startOfWeekComponents)!
        
        // Apply the week offset
        let startDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startOfWeek)!
        
        // Generate dates for the week
        var dates: [Date] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: i, to: startDate) {
                dates.append(date)
            }
        }
        
        visibleDates = dates
    }
    
    private func preserveSelectedDayOfWeek(weekday: Int) {
        // Find the date in visibleDates that has the same weekday
        if let newDate = visibleDates.first(where: { Calendar.current.component(.weekday, from: $0) == weekday }) {
            // Check if this date is not in the future
            if !newDate.isAfterDate(today) {
                selectedDate = newDate
                onDateSelected?(newDate)
            } else {
                // If the preserved day would be in the future, select today instead
                let today = Date()
                selectedDate = today
                onDateSelected?(today)
            }
        }
    }
    
    private func isFutureWeek(offset: Int) -> Bool {
        let calendar = Calendar.current
        let startOfWeekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let startOfWeek = calendar.date(from: startOfWeekComponents)!
        
        let weekStartDate = calendar.date(byAdding: .weekOfYear, value: offset, to: startOfWeek)!
        
        // If the first day of the week is after today's week, consider it a future week
        return calendar.compare(weekStartDate, to: startOfWeek, toGranularity: .weekOfYear) == .orderedDescending
    }
}

struct DateCircle: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isSelectable: Bool
    
    var body: some View {
        Text(dayNumber)
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(textColor)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .opacity(isSelectable ? 1.0 : 0.4) // Dim future dates
    }
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        }
        return .clear
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .blue
        } else {
            return .primary
        }
    }
}

private func calculateTargetSleepHours(wakeUpTime: Date, sleepTime: Date) -> Double {
    let calendar = Calendar.current
    
    // Handle case when sleep time is on the next day
    let sleepComponents = calendar.dateComponents([.hour, .minute], from: sleepTime)
    let wakeComponents = calendar.dateComponents([.hour, .minute], from: wakeUpTime)
    
    // Convert to minutes for easier calculation
    let sleepMinutes = sleepComponents.hour! * 60 + sleepComponents.minute!
    let wakeMinutes = wakeComponents.hour! * 60 + wakeComponents.minute!
    
    // If sleep time is after wake time, it means sleep spans across midnight
    let totalMinutes = sleepMinutes > wakeMinutes
        ? (24 * 60 - sleepMinutes) + wakeMinutes
        : wakeMinutes - sleepMinutes
        
    // Convert back to hours (with fraction)
    return Double(totalMinutes) / 60.0
}

// Extension to help with date comparison
extension Date {
    func isAfterDate(_ date: Date) -> Bool {
        return Calendar.current.compare(self, to: date, toGranularity: .day) == .orderedDescending
    }
    
    func isBeforeDate(_ date: Date) -> Bool {
        return Calendar.current.compare(self, to: date, toGranularity: .day) == .orderedAscending
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        HealthView()
    }
}
