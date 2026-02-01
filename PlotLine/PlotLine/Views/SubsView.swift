//
//  SubsView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 1/10/26.
//

import SwiftUI
import UserNotifications

struct SubsView: View {
    @EnvironmentObject var calendarVM: CalendarViewModel

    @State private var subscriptions: [SubscriptionItem] = []
    @State private var newName: String = ""
    @State private var newDueDate: Date = Date()
    @State private var showSavedAlert = false

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Subscriptions")
                        .font(.headline)
                    Text("Add reminders for recurring bills. We’ll notify you the day before they’re due.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Subscription")
                        .font(.headline)

                    TextField("Company name", text: $newName)
                        .textFieldStyle(.roundedBorder)

                    DatePicker("Due date", selection: $newDueDate, displayedComponents: .date)

                    Button("Add") {
                        addSubscription()
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your Subscriptions")
                        .font(.headline)

                    if subscriptions.isEmpty {
                        Text("No subscriptions yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(subscriptions) { sub in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sub.name)
                                        .font(.headline)
                                    Text("Due: \(sub.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    deleteSubscription(sub)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Subscriptions")
        .onAppear {
            requestNotificationPermission()
            Task {
                await calendarVM.fetchEvents()
                fetchSubscriptions()
            }
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func addSubscription() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !subscriptions.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            subscriptions.append(SubscriptionItem(name: trimmed, cost: "", dueDate: newDueDate))
            saveSubscriptions()
        }
        newName = ""
    }

    private func deleteSubscription(_ sub: SubscriptionItem) {
        subscriptions.removeAll { $0.name.caseInsensitiveCompare(sub.name) == .orderedSame }
        removeCalendarEvent(for: sub)
        saveSubscriptions()
    }

    private func fetchSubscriptions() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/\(username)") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, !data.isEmpty,
                  let decoded = try? JSONDecoder().decode(SubscriptionMapResponse.self, from: data) else {
                return
            }
            let list = decoded.subscriptions.map { (name, subData) in
                SubscriptionItem(name: name, cost: "", dueDate: subData.dueDate)
            }
            DispatchQueue.main.async {
                self.subscriptions = list
                for sub in list {
                    self.ensureCalendarEvent(for: sub)
                    self.scheduleMonthlyReminder(for: sub)
                }
                self.mergeFromCalendar()
            }
        }.resume()
    }

    private func mergeFromCalendar() {
        let calendarSubs = calendarVM.events.filter {
            $0.eventType.lowercased().hasPrefix("subscription")
        }

        var merged = subscriptions
        for ev in calendarSubs {
            if !merged.contains(where: { $0.name.caseInsensitiveCompare(ev.title) == .orderedSame }) {
                merged.append(SubscriptionItem(name: ev.title, cost: "", dueDate: ev.startDate))
            }
        }
        if merged.count != subscriptions.count {
            subscriptions = merged
            saveSubscriptions()
        }
    }

    private func saveSubscriptions() {
        var dict: [String: SubscriptionData] = [:]
        for sub in subscriptions {
            dict[sub.name] = SubscriptionData(name: sub.name, cost: "", dueDate: sub.dueDate)
            ensureCalendarEvent(for: sub)
            scheduleMonthlyReminder(for: sub)
        }

        let payload = SubscriptionUpload(username: username, subscriptions: dict)
        guard let body = try? JSONEncoder().encode(payload),
              let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { self.showSavedAlert = true }
        }.resume()
    }

    private func ensureCalendarEvent(for sub: SubscriptionItem) {
        let exists = calendarVM.events.contains {
            $0.eventType.lowercased().hasPrefix("subscription") &&
            $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
        }
        if !exists {
            calendarVM.createEvent(
                title: sub.name,
                description: "Subscription reminder",
                startDate: sub.dueDate,
                endDate: sub.dueDate,
                eventType: "subscription",
                recurrence: "monthly",
                invitedFriends: []
            )
        }
    }

    private func removeCalendarEvent(for sub: SubscriptionItem) {
        let matches = calendarVM.events.filter {
            $0.eventType.lowercased().hasPrefix("subscription") &&
            $0.title.caseInsensitiveCompare(sub.name) == .orderedSame
        }
        for ev in matches {
            calendarVM.deleteEvent(ev.id)
        }
    }

    private func scheduleMonthlyReminder(for sub: SubscriptionItem) {
        let center = UNUserNotificationCenter.current()
        let id = "subscription-reminder-\(sub.name.lowercased())"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        var comps = Calendar.current.dateComponents([.day], from: sub.dueDate)
        let day = comps.day ?? 1
        if day == 1 {
            comps.day = 1
            comps.hour = 9
            comps.minute = 0
        } else {
            comps.day = day - 1
            comps.hour = 9
            comps.minute = 0
        }

        let content = UNMutableNotificationContent()
        content.title = "Subscription Reminder"
        content.body = day == 1 ? "\(sub.name) is due today." : "\(sub.name) is due tomorrow."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
}

#Preview {
    SubsView()
        .environmentObject(CalendarViewModel())
}
