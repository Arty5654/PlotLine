import SwiftUI
import UserNotifications

struct AddEventSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var friendVM: FriendsViewModel

    let defaultDate: Date
    let existingEvents: [Event]
    let editingEventId: String? // nil for new events, set for editing

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var startDate: Date
    @State private var endDate: Date

    @State private var isRecurring: Bool = false
    @State private var recurrence: String = "none"

    @State private var isRange: Bool = false

    @State private var isSubscription: Bool = false
    @State private var monthlyCost: String = ""

    @State private var showFriendDropdown = false
    @State private var selectedFriends: [Friend] = []
    @State private var showDuplicateAlert = false

    // Adaptive color: white in dark mode, blue in light mode
    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    // Reminder selections — id is secondsBefore (stable across sessions)
    struct ReminderOption: Identifiable {
        let id: TimeInterval
        let label: String
        var secondsBefore: TimeInterval { id }
    }
    private let reminderOptions: [ReminderOption] = [
        ReminderOption(id: 15 * 60,      label: "15 minutes before"),
        ReminderOption(id: 60 * 60,      label: "1 hour before"),
        ReminderOption(id: 24 * 60 * 60, label: "1 day before"),
        ReminderOption(id: 0,            label: "At start time")
    ]
    @State private var selectedReminders: Set<TimeInterval> = []
    @State private var internalEventId: String = ""

    @State private var friendsCanSee: Bool = true
    @State private var selectedPublishCalendars: Set<String> = []

    // Friends whose calendars the current user can publish to (received "add" access)
    let publishableFriendCalendars: [String]

    // onSave: (eventId, title, description, start, end, recurrence, friends, eventType, friendsCanSee, publishToCalendars)
    let onSave: (String, String, String, Date, Date, String, [String], String, Bool, [String]) -> Void

    // MARK: - Init for creating a new event
    init(defaultDate: Date, existingEvents: [Event] = [], publishableFriendCalendars: [String] = [], onSave: @escaping (String, String, String, Date, Date, String, [String], String, Bool, [String]) -> Void) {
        self.defaultDate = defaultDate
        self.existingEvents = existingEvents
        self.editingEventId = nil
        self.publishableFriendCalendars = publishableFriendCalendars
        self.onSave = onSave

        _title = State(initialValue: "")
        _description = State(initialValue: "")
        _startDate = State(initialValue: defaultDate)
        _endDate = State(initialValue: defaultDate)
        _recurrence = State(initialValue: "none")
        _internalEventId = State(initialValue: UUID().uuidString)
        _selectedReminders = State(initialValue: [])
        _friendsCanSee = State(initialValue: true)
    }

    // MARK: - Init for editing an existing event
    init(existingEvent: Event, existingEvents: [Event] = [], onSave: @escaping (String, String, String, Date, Date, String, [String], String, Bool, [String]) -> Void) {
        self.defaultDate = existingEvent.startDate
        self.existingEvents = existingEvents
        self.editingEventId = existingEvent.id
        self.publishableFriendCalendars = []
        self.onSave = onSave

        let isSub = existingEvent.eventType.lowercased().hasPrefix("subscription")
        _title = State(initialValue: existingEvent.title)
        _startDate = State(initialValue: existingEvent.startDate)
        _endDate = State(initialValue: existingEvent.endDate)
        _isRange = State(initialValue: !Calendar.current.isDate(existingEvent.startDate, inSameDayAs: existingEvent.endDate))
        _isRecurring = State(initialValue: existingEvent.recurrence != "none")
        _recurrence = State(initialValue: existingEvent.recurrence)
        _isSubscription = State(initialValue: isSub)
        _selectedFriends = State(initialValue: existingEvent.invitedFriends.filter { !$0.contains("-creator-user-") }
            .map { Friend(username: $0) })
        _internalEventId = State(initialValue: existingEvent.id)
        _friendsCanSee = State(initialValue: existingEvent.friendsCanSee)

        // Restore previously saved reminder selections
        let saved = UserDefaults.standard.array(forKey: "event_reminders_\(existingEvent.id)") as? [Double] ?? []
        _selectedReminders = State(initialValue: Set(saved.map { TimeInterval($0) }))

        if isSub {
            let desc = existingEvent.description
            if let range = desc.range(of: #"\$(\d+\.?\d*)"#, options: .regularExpression) {
                _monthlyCost = State(initialValue: String(desc[range].dropFirst()))
                let cleanDesc = desc.replacingOccurrences(of: #"Subscription reminder\s*\(\$\d+\.?\d*\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                _description = State(initialValue: cleanDesc)
            } else {
                _monthlyCost = State(initialValue: "")
                _description = State(initialValue: desc)
            }
        } else {
            _description = State(initialValue: existingEvent.description)
        }
    }

    // Check if an event with the same title exists on the same day
    private var hasDuplicateTitle: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        let startOfDay = Calendar.current.startOfDay(for: startDate)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return false }

        return existingEvents.contains { event in
            // Skip the event we're editing
            if let editingId = editingEventId, event.id == editingId { return false }

            // Check if event is on the same day
            let eventOnSameDay = event.startDate < endOfDay && event.endDate >= startOfDay

            // Check if title matches (case-insensitive)
            let titleMatches = event.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTitle.lowercased()

            return eventOnSameDay && titleMatches
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasDuplicateTitle
    }

    var body: some View {
        NavigationView {
            Form {
                // Event type
                Section(header: Text("Event Type").foregroundColor(adaptiveTextColor)) {
                    Toggle("Subscription", isOn: $isSubscription)
                        .onChange(of: isSubscription) { on in
                            if on {
                                isRecurring = true
                                recurrence = "monthly"
                            }
                        }
                    if isSubscription {
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("Monthly cost", text: $monthlyCost)
                                .keyboardType(.decimalPad)
                                .accentColor(adaptiveTextColor)
                        }
                    }
                }

                // Event detail fields
                Section(header: Text("Event Details").foregroundColor(adaptiveTextColor)) {
                    TextField("Title", text: $title)
                        .accentColor(adaptiveTextColor)
                    if !isSubscription {
                        TextField("Description", text: $description)
                            .accentColor(adaptiveTextColor)
                    }
                }

                // Date selection fields
                Section(header: Text("Dates & Times").foregroundColor(adaptiveTextColor)) {
                    Toggle("Multiple Days?", isOn: $isRange)
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        .accentColor(adaptiveTextColor)

                    if isRange {
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                            .accentColor(adaptiveTextColor)
                    }
                }

                // Recurrence options
                Section(header: Text("Repeat").foregroundColor(adaptiveTextColor)) {
                    Toggle("Recurring Event?", isOn: $isRecurring)
                        .onChange(of: isRecurring) { on in
                            if !on { recurrence = "none" }
                            else if recurrence == "none" {
                                recurrence = "weekly" // sensible default when turning on
                            }
                        }
                    if isRecurring {
                        Picker("Frequency", selection: $recurrence) {
                            Text("Every Week").tag("weekly")
                            Text("Every other week").tag("biweekly")
                            Text("Every Month").tag("monthly")
                            Text("Every Year").tag("yearly")
                        }
                        .accentColor(adaptiveTextColor)
                    }
                }


                Section(header: Text("Invite Friends").foregroundColor(adaptiveTextColor)) {
                    // Button to toggle the friend dropdown
                    Button(action: {
                        withAnimation {
                            showFriendDropdown.toggle()
                        }
                    }) {
                        HStack {
                            Text("Invite Friends")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: showFriendDropdown ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    if showFriendDropdown {
                        let availableFriends = friendVM.friends
                            .map { Friend(username: $0) }
                            .filter { !$0.id.contains("-creator-user-") && !selectedFriends.contains($0) }

                        if availableFriends.isEmpty {
                            Text(friendVM.friends.isEmpty ? "No friends added yet" : "All friends already invited")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                Divider()
                                ScrollView {
                                    VStack(spacing: 0) {
                                        ForEach(availableFriends) { friend in
                                            Button(action: {
                                                withAnimation {
                                                    selectedFriends.append(friend)
                                                }
                                            }) {
                                                HStack {
                                                    Text(friend.name)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Image(systemName: "plus.circle.fill")
                                                        .foregroundColor(adaptiveTextColor)
                                                }
                                                .padding(.vertical, 8)
                                                .padding(.horizontal, 12)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            Divider()
                                        }
                                    }
                                }
                                .frame(maxHeight: 150)
                            }
                        }
                    }

                    if !selectedFriends.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedFriends) { friend in
                                    HStack(spacing: 4) {
                                        Text(friend.name)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Button(action: {
                                            withAnimation {
                                                if let index = selectedFriends.firstIndex(of: friend) {
                                                    selectedFriends.remove(at: index)
                                                }
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.gray.opacity(0.2))
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Friends visibility
                Section(header: Text("Visibility").foregroundColor(adaptiveTextColor)) {
                    Toggle("Friends can see this event", isOn: $friendsCanSee)
                }

                // Publish to friend calendars (only for new events, only when access exists)
                if editingEventId == nil && !publishableFriendCalendars.isEmpty {
                    Section(header: Text("Also Publish To").foregroundColor(adaptiveTextColor)) {
                        ForEach(publishableFriendCalendars, id: \.self) { friend in
                            Toggle(friend, isOn: Binding<Bool>(
                                get: { selectedPublishCalendars.contains(friend) },
                                set: { on in
                                    if on { selectedPublishCalendars.insert(friend) }
                                    else { selectedPublishCalendars.remove(friend) }
                                }
                            ))
                        }
                    }
                }

                // Notifications
                Section(header: Text("Reminders").foregroundColor(adaptiveTextColor)) {
                    ForEach(reminderOptions) { opt in
                        Toggle(isOn: Binding<Bool>(
                            get: { selectedReminders.contains(opt.secondsBefore) },
                            set: { isOn in
                                if isOn { selectedReminders.insert(opt.secondsBefore) }
                                else { selectedReminders.remove(opt.secondsBefore) }
                            }
                        )) {
                            Text(opt.label)
                        }
                    }
                }
            }
            .tint(.blue)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                requestNotificationPermission()
                if friendVM.friends.isEmpty {
                    let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
                    Task { await friendVM.loadFriends(for: username) }
                }
            }
            .navigationBarTitle("Add Event", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    if hasDuplicateTitle {
                        showDuplicateAlert = true
                    } else {
                        let finalEndDate = isRange ? endDate : startDate

                        // Persist reminder selections and reschedule (cancels old ones first)
                        UserDefaults.standard.set(Array(selectedReminders), forKey: "event_reminders_\(internalEventId)")
                        scheduleReminders(for: internalEventId, eventTitle: title, start: startDate)

                        let eventType = isSubscription ? "subscription" : "user"
                        var finalDescription = description
                        if isSubscription {
                            let costStr = monthlyCost.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let cost = Double(costStr), cost > 0 {
                                finalDescription = "Subscription reminder ($\(String(format: "%.2f", cost)))"
                            } else {
                                finalDescription = "Subscription reminder"
                            }
                        }

                        onSave(internalEventId, title, finalDescription, startDate, finalEndDate, recurrence, selectedFriends.map { $0.id }, eventType, friendsCanSee, Array(selectedPublishCalendars))
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(!canSave)
            )
            .alert("Duplicate Event", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("An event with this name already exists on this day. Please choose a different name.")
            }
        }
        .tint(adaptiveTextColor)
    }
}

private extension AddEventSheet {
    func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleReminders(for eventId: String, eventTitle: String, start: Date) {
        let center = UNUserNotificationCenter.current()

        // Cancel all existing notifications for this event before rescheduling
        let allIds = reminderOptions.map { "reminder_\(eventId)_\(Int($0.secondsBefore))" }
        center.removePendingNotificationRequests(withIdentifiers: allIds)

        let selectedOpts = reminderOptions.filter { selectedReminders.contains($0.secondsBefore) }
        guard !selectedOpts.isEmpty else { return }

        let eventName = eventTitle.isEmpty ? "Event" : eventTitle
        let dateFormatter = ISO8601DateFormatter()

        for opt in selectedOpts {
            let triggerDate = start.addingTimeInterval(-opt.secondsBefore)
            if triggerDate < Date() { continue }

            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let content = UNMutableNotificationContent()
            content.title = "Upcoming Event"
            content.body = switch opt.secondsBefore {
                case 0:         "\(eventName) is starting now!"
                case 15 * 60:  "\(eventName) starts in 15 minutes"
                case 60 * 60:  "\(eventName) starts in 1 hour"
                default:        "\(eventName) starts in 24 hours"
            }
            content.sound = .default
            content.userInfo = [
                "eventTitle": eventTitle,
                "eventDate": dateFormatter.string(from: start),
                "navigateTo": "calendar",
                "secondsBefore": opt.secondsBefore,
                "showDayView": opt.secondsBefore < 24 * 60 * 60
            ]

            let request = UNNotificationRequest(
                identifier: "reminder_\(eventId)_\(Int(opt.secondsBefore))",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}


struct Friend: Identifiable, Equatable {
    let id: String
    var name: String { id }

    init(username: String) {
        self.id = username
    }
}
