//
//  SleepScheduleView.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/2/25.
//

import SwiftUI
import UserNotifications
// Notification Logic copied from WeeklyMonthlyCostView.swift

struct SleepScheduleView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var sleepSchedule: SleepSchedule
    @State private var originalSchedule: SleepSchedule
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    private let sleepAPI = SleepAPI()
    
    // Initialize with default values (9am wake up, 12am sleep)
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
        
        let schedule = SleepSchedule(wakeUpTime: wakeUpTime, sleepTime: sleepTime)
        _sleepSchedule = State(initialValue: schedule)
        _originalSchedule = State(initialValue: schedule)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section() {
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
                
                // Preview notification time section
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
                
                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Spacer()
                        }
                    } else {
                        Button("Save Changes") {
                            Task {
                                await saveSleepSchedule()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(!hasChanges)
                    }
                }
            }
            .navigationTitle("Sleep Schedule")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                Task {
                    await loadSleepSchedule()
                    checkNotificationPermission()
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
    
    // Check if there are unsaved changes
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
    
    // MARK: - Notification Functions
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus != .authorized {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                }
            }
        }
    }
    
    private func scheduleBedtimeReminder() {
        // Remove any existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
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
        
        // Debug the next trigger date
        if let nextTriggerDate = trigger.nextTriggerDate() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            let timeUntilTrigger = nextTriggerDate.timeIntervalSince(Date())
            let hours = Int(timeUntilTrigger) / 3600
            let minutes = (Int(timeUntilTrigger) % 3600) / 60
        }
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: "bedtimeReminder",
            content: content,
            trigger: trigger
        )
        
        // Add the notification request
        UNUserNotificationCenter.current().add(request)
    }
    
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Bedtime Reminder Test"
        content.body = "This is a test of your bedtime reminder notification!"
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive
        
        // Create a trigger for 5 seconds from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: "bedtimeReminderTest",
            content: content,
            trigger: trigger
        )
        
        // Add the notification request
        UNUserNotificationCenter.current().add(request)
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

struct SleepScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        SleepScheduleView()
    }
}
