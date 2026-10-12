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
    @State private var location: String = ""
    @State private var startDate: Date
    @State private var endDate: Date

    @State private var isRecurring: Bool = false
    @State private var recurrence: String = "none"
    @State private var endsOnDate: Bool = false
    @State private var repeatEnd: Date = Date()
    @State private var showScopeChoice = false

    @State private var isRange: Bool = false

    @State private var isSubscription: Bool = false
    @State private var monthlyCost: String = ""

    @State private var showFriendDropdown = false
    @State private var selectedFriends: [Friend] = []
    @State private var showDuplicateAlert = false


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

    // the event being edited (nil when adding one)
    let original: Event?
    let onSave: (EventDraft) -> Void

    // MARK: - Init for creating a new event
    init(defaultDate: Date, existingEvents: [Event] = [], publishableFriendCalendars: [String] = [], onSave: @escaping (EventDraft) -> Void) {
        self.defaultDate = defaultDate
        self.existingEvents = existingEvents
        self.editingEventId = nil
        self.original = nil
        self.publishableFriendCalendars = publishableFriendCalendars
        self.onSave = onSave

        _title = State(initialValue: "")
        _description = State(initialValue: "")
        _startDate = State(initialValue: defaultDate)
        _endDate = State(initialValue: defaultDate)
        _recurrence = State(initialValue: "none")
        _repeatEnd = State(initialValue: Calendar.current.date(byAdding: .month, value: 3, to: defaultDate) ?? defaultDate)
        _internalEventId = State(initialValue: UUID().uuidString)
        _selectedReminders = State(initialValue: [])
        _friendsCanSee = State(initialValue: true)
    }

    // MARK: - Init for editing an existing event
    init(existingEvent: Event, existingEvents: [Event] = [], onSave: @escaping (EventDraft) -> Void) {
        self.defaultDate = existingEvent.startDate
        self.existingEvents = existingEvents
        self.editingEventId = existingEvent.id
        self.original = existingEvent
        self.publishableFriendCalendars = []
        self.onSave = onSave

        let isSub = existingEvent.eventType.lowercased().hasPrefix("subscription")
        _title = State(initialValue: existingEvent.title)
        _location = State(initialValue: existingEvent.location ?? "")
        _startDate = State(initialValue: existingEvent.startDate)
        _endDate = State(initialValue: existingEvent.endDate)
        _isRange = State(initialValue: !Calendar.current.isDate(existingEvent.startDate, inSameDayAs: existingEvent.endDate))
        _isRecurring = State(initialValue: existingEvent.recurrence != "none")
        _recurrence = State(initialValue: existingEvent.recurrence)
        _endsOnDate = State(initialValue: existingEvent.recurrenceEnd != nil)
        _repeatEnd = State(initialValue: existingEvent.recurrenceEnd.flatMap(Event.endOfDay)
                           ?? Calendar.current.date(byAdding: .month, value: 3, to: existingEvent.startDate) ?? existingEvent.startDate)
        _isSubscription = State(initialValue: isSub)
        _selectedFriends = State(initialValue: existingEvent.invitedFriends.filter { !$0.contains("-creator-user-") }
            .map { Friend(username: $0) })
        _internalEventId = State(initialValue: existingEvent.id)
        _friendsCanSee = State(initialValue: existingEvent.friendsCanSee)

        // Restore previously saved reminder selections
        _selectedReminders = State(initialValue: EventReminders.saved(for: existingEvent))

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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (importedFrom != nil || !hasDuplicateTitle)
    }

    /// Apple or Google Calendar: those details are changed there (the next sync would undo them here)
    private var importedFrom: String? { original?.importedFrom }

    /// an imported rule the picker can't show ("every 3 weeks on Mon and Wed")
    private var customRule: RecurrenceRule? {
        guard let text = original?.recurrenceRule, let rule = RecurrenceRule(rrule: text),
              rule.name == nil || importedFrom != nil else { return nil }
        return rule
    }

    private var recurrenceEndKey: String? {
        isRecurring && endsOnDate ? Recurrence.dayKey(repeatEnd) : nil
    }

    /// the repeat settings were changed: then the change can only be for the whole series
    private var repeatChanged: Bool {
        guard let original else { return false }
        return recurrence != original.recurrence || recurrenceEndKey != original.recurrenceEnd
    }

    var body: some View {
        NavigationStack {
            Form {
                if let importedFrom {
                    Section {
                        Label("From \(importedFrom). Change the title, time, place or repeat there. Reminders, invited friends and who can see it are set here.",
                              systemImage: "lock")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                // Event type
                if importedFrom == nil {
                Section(header: Text("Event Type")) {
                    Toggle("Subscription", isOn: $isSubscription)
                        .onChange(of: isSubscription) { _, on in
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
                        }
                    }
                }
                }

                // Event detail fields
                Section(header: Text("Event Details")) {
                    TextField("Title", text: $title)
                    if !isSubscription {
                        TextField("Description", text: $description)
                        TextField("Location", text: $location)
                            .textContentType(.fullStreetAddress)
                    }
                }
                .disabled(importedFrom != nil)

                // Date selection fields
                Section(header: Text("Dates & Times")) {
                    Toggle("Multiple Days?", isOn: $isRange)
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])

                    if isRange {
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
                .disabled(importedFrom != nil)

                // Recurrence options
                Section(header: Text("Repeat")) {
                    if let customRule {
                        Label(customRule.summary, systemImage: "repeat")
                    } else {
                        Toggle("Recurring Event?", isOn: $isRecurring)
                            .onChange(of: isRecurring) { _, on in
                                if !on { recurrence = "none" }
                                else if recurrence == "none" {
                                    recurrence = "weekly" // sensible default when turning on
                                }
                            }
                        if isRecurring {
                            Picker("Frequency", selection: $recurrence) {
                                Text("Every Day").tag("daily")
                                Text("Every Weekday (Mon–Fri)").tag("weekdays")
                                Text("Every Week").tag("weekly")
                                Text("Every other week").tag("biweekly")
                                Text("Every Month").tag("monthly")
                                Text("Every Year").tag("yearly")
                            }
                            Toggle("End Repeat", isOn: $endsOnDate)
                            if endsOnDate {
                                DatePicker("Last Day", selection: $repeatEnd, in: startDate..., displayedComponents: .date)
                            }
                        }
                    }
                }
                .disabled(importedFrom != nil)


                Section(header: Text("Invite Friends")) {
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
                                                        .foregroundColor(PLColor.tint)
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
                Section(header: Text("Visibility")) {
                    Toggle("Friends can see this event", isOn: $friendsCanSee)
                }

                // Publish to friend calendars (only for new events, only when access exists)
                if editingEventId == nil && !publishableFriendCalendars.isEmpty {
                    Section(header: Text("Also Publish To")) {
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
                Section(header: Text("Reminders")) {
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
            .navigationBarTitle(original == nil ? "Add Event" : "Edit Event", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    if importedFrom == nil && hasDuplicateTitle {
                        showDuplicateAlert = true
                    } else if let original, original.isRepeating, importedFrom == nil {
                        showScopeChoice = true // this date, or every date?
                    } else {
                        save(scope: .allEvents)
                    }
                }
                .disabled(!canSave)
            )
            .confirmationDialog("This is a repeating event.", isPresented: $showScopeChoice, titleVisibility: .visible) {
                if !repeatChanged {
                    Button("Save for This Event Only") { save(scope: .thisEvent) }
                }
                Button("Save for All Events") { save(scope: .allEvents) }
                Button("Cancel", role: .cancel) {}
            } message: {
                if repeatChanged {
                    Text("Changing how it repeats applies to every date.")
                }
            }
            .alert("Duplicate Event", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("An event with this name already exists on this day. Please choose a different name.")
            }
        }
        .tint(PLColor.accent)
    }

    private func save(scope: CalendarViewModel.RepeatScope) {
                        let finalEndDate = isRange ? endDate : startDate


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

                        onSave(EventDraft(id: internalEventId, title: title, description: finalDescription,
                                          start: startDate, end: finalEndDate, recurrence: recurrence,
                                          recurrenceEnd: recurrenceEndKey, invitedFriends: selectedFriends.map { $0.id },
                                          eventType: eventType, friendsCanSee: friendsCanSee,
                                          publishTo: Array(selectedPublishCalendars),
                                          location: isSubscription ? "" : location.trimmingCharacters(in: .whitespacesAndNewlines),
                                          reminders: selectedReminders, scope: scope))
                        presentationMode.wrappedValue.dismiss()
    }
}

/// what the event editor saves
struct EventDraft {
    var id: String
    var title: String
    var description: String
    var start: Date
    var end: Date
    var recurrence: String
    var recurrenceEnd: String?
    var invitedFriends: [String]
    var eventType: String
    var friendsCanSee: Bool
    var publishTo: [String]
    var location: String
    /// seconds before the start; for a repeating event, every date (or just this one with `.thisEvent`)
    var reminders: Set<TimeInterval> = []
    var scope: CalendarViewModel.RepeatScope = .allEvents

    /// `event` with these changes. An imported event only takes the PlotLine parts (friends, who can see it).
    func applied(to event: Event) -> Event {
        var e = event
        if event.importedFrom == nil {
            e.title = title
            e.description = description
            e.startDate = start
            e.endDate = end
            e.recurrence = recurrence
            e.recurrenceEnd = recurrence == "none" ? nil : recurrenceEnd
            e.eventType = eventType
            e.location = location.isEmpty ? nil : location
        }
        e.invitedFriends = invitedFriends
        e.friendsCanSee = friendsCanSee
        return e
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

}


struct Friend: Identifiable, Equatable {
    let id: String
    var name: String { id }

    init(username: String) {
        self.id = username
    }
}
