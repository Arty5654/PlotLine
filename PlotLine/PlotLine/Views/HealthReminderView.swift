//
//  HealthReminderView.swift
//  PlotLine
//
//  Created by Yash Mehta on 5/1/25.
//


import SwiftUI
import UserNotifications

struct HealthReminderView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // Sleep schedule state
    @State private var sleepSchedule: SleepSchedule
    @State private var originalSchedule: SleepSchedule
    
    // Mood tracking state
    @State private var moodTrackingEnabled: Bool = true
    @State private var moodReminderTime: Date
    
    // Sleep tracking state
    @State private var sleepTrackingEnabled: Bool = true
    @State private var sleepLogReminderTime: Date
    
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    private let sleepAPI = SleepAPI()
    
    // Initialize with default values
    init() {
        let calendar = Calendar.current
        
        // Default wake up time (9:00 AM)
        var wakeComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        wakeComponents.hour = 9
        wakeComponents.minute = 0
        let wakeUpTime = calendar.date(from: wakeComponents) ?? Date()
        
        // Default sleep time (12:00 AM / Midnight)
        var sleepComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        sleepComponents.hour = 0
        sleepComponents.minute = 0
        let sleepTime = calendar.date(from: sleepComponents) ?? Date()
        
        // Default mood reminder time (8:00 PM)
        var moodComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        moodComponents.hour = 20
        moodComponents.minute = 0
        let moodTime = calendar.date(from: moodComponents) ?? Date()
        
        // Default sleep log reminder time (9:30 AM)
        var sleepLogComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        sleepLogComponents.hour = 9
        sleepLogComponents.minute = 30
        let sleepLogTime = calendar.date(from: sleepLogComponents) ?? Date()
        
        let schedule = SleepSchedule(wakeUpTime: wakeUpTime, sleepTime: sleepTime)
        _sleepSchedule = State(initialValue: schedule)
        _originalSchedule = State(initialValue: schedule)
        _moodReminderTime = State(initialValue: moodTime)
        _sleepLogReminderTime = State(initialValue: sleepLogTime)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Sleep schedule section
                Section(header: Text("Sleep Schedule")) {
                    HStack {
                        Text("Wake Up Time:")
                        Spacer()
                        DatePicker("", selection: $sleepSchedule.wakeUpTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.vertical, 8)
                    
                    HStack {
                        Text("Sleep Time:")
                        Spacer()
                        DatePicker("", selection: $sleepSchedule.sleepTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.vertical, 8)
                }
                
                // Bedtime reminder section
                Section(header: Text("Bedtime Reminder")) {
                    HStack {
                        Text("Reminder Time:")
                        Spacer()
                        let reminderTime = calculateReminderTime(from: sleepSchedule.sleepTime)
                        Text(formatTime(reminderTime))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Text("You'll receive a notification at this time to start winding down for bed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Sleep tracking reminder section
                Section(header: Text("Sleep Tracking")) {
                    Toggle("Enable Sleep Logging Reminders", isOn: $sleepTrackingEnabled)
                    
                    if sleepTrackingEnabled {
                        HStack {
                            Text("Reminder Time:")
                            Spacer()
                            DatePicker("", selection: $sleepLogReminderTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)
                        
                        Text("You'll receive a daily reminder to log your sleep data at this time.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Mood tracking reminder section
                Section(header: Text("Mood Tracking")) {
                    Toggle("Enable Mood Tracking Reminders", isOn: $moodTrackingEnabled)
                    
                    if moodTrackingEnabled {
                        HStack {
                            Text("Reminder Time:")
                            Spacer()
                            DatePicker("", selection: $moodReminderTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)
                        
                        Text("You'll receive a daily reminder to log your mood at this time.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Save section
                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Spacer()
                        }
                    } else {
                        Button("Save All Settings") {
                            Task {
                                await saveAllReminders()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Health Reminders")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                Task {
                    await loadSleepSchedule()
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // Update the saveAllReminders function to properly save to SleepAPI
    private func saveAllReminders() async {
        isLoading = true
        
        do {
                // Update sleep schedule with notification preferences
                var updatedSchedule = sleepSchedule
                updatedSchedule.sleepTrackingEnabled = sleepTrackingEnabled
                updatedSchedule.moodTrackingEnabled = moodTrackingEnabled
                updatedSchedule.sleepLogReminderTime = sleepLogReminderTime
                updatedSchedule.moodReminderTime = moodReminderTime
                
                // Save to the API
                try await sleepAPI.saveSleepSchedule(updatedSchedule)
                
                // Update local reference to reflect saved state
                DispatchQueue.main.async {
                    self.originalSchedule = updatedSchedule
                    self.sleepSchedule = updatedSchedule
                }
                
                // Schedule notifications based on saved preferences
                scheduleBedtimeReminder()
                
                if sleepTrackingEnabled {
                    scheduleSleepTrackingReminder()
                } else {
                    removeNotification(identifier: "sleepTrackingReminder")
                }
                
                if moodTrackingEnabled {
                    scheduleMoodTrackingReminder()
                } else {
                    removeNotification(identifier: "moodTrackingReminder")
                }
                
                // Update UI
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.showSuccess("Saved", "Your health reminders have been updated.")
                }
        } catch URLError.userAuthenticationRequired {
            DispatchQueue.main.async {
                self.isLoading = false
                self.showError("Not Logged In", "Please log in to save your health settings.")
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.showError("Save Failed", "Could not save your health settings: \(error.localizedDescription)")
            }
        }
    }
    
    // Check if sleep schedule has unsaved changes
    private var hasChanges: Bool {
        return !Calendar.current.isDate(sleepSchedule.wakeUpTime, equalTo: originalSchedule.wakeUpTime, toGranularity: .minute) ||
               !Calendar.current.isDate(sleepSchedule.sleepTime, equalTo: originalSchedule.sleepTime, toGranularity: .minute)
    }
    
    // Load sleep schedule
    private func loadSleepSchedule() async {
        isLoading = true
        
        do {
            let schedule = try await sleepAPI.fetchSleepSchedule()
            sleepSchedule = schedule
            originalSchedule = schedule
            isLoading = false
        } catch URLError.userAuthenticationRequired {
            isLoading = false
            showError("Not Logged In", "Please log in to view your sleep schedule.")
        } catch {
            isLoading = false
            showError("Failed to Load", "Using default schedule: \(error.localizedDescription)")
        }
    }
    
    // Save sleep schedule
    private func saveSleepSchedule() async {
        isLoading = true
        
        do {
            try await sleepAPI.saveSleepSchedule(sleepSchedule)
            originalSchedule = sleepSchedule
            
            // Schedule the notification after saving the sleep schedule
            scheduleBedtimeReminder()
            
            isLoading = false
            showSuccess("Saved", "Your sleep schedule has been updated.")
        } catch URLError.userAuthenticationRequired {
            isLoading = false
            showError("Not Logged In", "Please log in to save your sleep schedule.")
        } catch {
            isLoading = false
            showError("Save Failed", "Could not save your sleep schedule: \(error.localizedDescription)")
        }
    }
    
    private func scheduleBedtimeReminder() {
        // Create a date component for the sleep time
        let sleepTime = sleepSchedule.sleepTime
        let calendar = Calendar.current
        
        // Create components for 1 hour before sleep time
        var reminderComponents = calendar.dateComponents([.hour, .minute], from: sleepTime)
        
        // Adjust to be 1 hour earlier
        if let hour = reminderComponents.hour {
            reminderComponents.hour = hour - 1
        }
        
        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = "Time to Wind Down"
        content.body = "Your bedtime is in 1 hour. Start preparing for sleep!"
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive
        
        // Create a daily trigger at the calculated time
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: true)
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: "bedtimeReminder",
            content: content,
            trigger: trigger
        )
        
        // Remove existing notification before adding a new one
        removeNotification(identifier: "bedtimeReminder")
        
        // Add the notification request
        UNUserNotificationCenter.current().add(request)
    }
    
    private func scheduleSleepTrackingReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Sleep Log Reminder"
        content.body = "Don't forget to log your sleep from last night!"
        content.sound = UNNotificationSound.default
        
        // Create date components for the reminder time
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: sleepLogReminderTime)
        
        // Create a daily trigger at the specified time
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: "sleepTrackingReminder",
            content: content,
            trigger: trigger
        )
        
        // Remove existing notification before adding a new one
        removeNotification(identifier: "sleepTrackingReminder")
        
        // Add the notification request
        UNUserNotificationCenter.current().add(request)
    }
    
    private func scheduleMoodTrackingReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Mood Check-in"
        content.body = "How are you feeling today? Take a moment to track your mood."
        content.sound = UNNotificationSound.default
        
        // Create date components for the reminder time
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: moodReminderTime)
        
        // Create a daily trigger at the specified time
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: "moodTrackingReminder",
            content: content,
            trigger: trigger
        )
        
        // Remove existing notification before adding a new one
        removeNotification(identifier: "moodTrackingReminder")
        
        // Add the notification request
        UNUserNotificationCenter.current().add(request)
    }
    
    private func removeNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    // MARK: - Helper Functions
    
    private func calculateReminderTime(from sleepTime: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .hour, value: -1, to: sleepTime) ?? sleepTime
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
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

struct HealthReminderView_Previews: PreviewProvider {
    static var previews: some View {
        HealthReminderView()
    }
}
