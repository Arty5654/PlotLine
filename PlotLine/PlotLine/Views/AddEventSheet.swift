import SwiftUI
import UserNotifications

struct AddEventSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var friendVM: FriendsViewModel

    let defaultDate: Date

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var startDate: Date
    @State private var endDate: Date

    @State private var isRecurring: Bool = false
    @State private var recurrence: String = "none"

    @State private var isRange: Bool = false

    @State private var showFriendDropdown = false
    @State private var selectedFriends: [Friend] = []

    // Adaptive color: white in dark mode, blue in light mode
    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    // Reminder selections
    struct ReminderOption: Identifiable {
        let id = UUID()
        let label: String
        let secondsBefore: TimeInterval
    }
    private let reminderOptions: [ReminderOption] = [
        ReminderOption(label: "15 minutes before", secondsBefore: 15 * 60),
        ReminderOption(label: "1 hour before", secondsBefore: 60 * 60),
        ReminderOption(label: "1 day before", secondsBefore: 24 * 60 * 60),
        ReminderOption(label: "At start time", secondsBefore: 0)
    ]
    @State private var selectedReminders: Set<UUID> = []


    let onSave: (String, String, Date, Date, String, [String]) -> Void

    // MARK: - Init for creating a new event
    init(defaultDate: Date, onSave: @escaping (String, String, Date, Date, String, [String]) -> Void) {
        self.defaultDate = defaultDate
        self.onSave = onSave

        _title = State(initialValue: "")
        _description = State(initialValue: "")
        _startDate = State(initialValue: defaultDate)
        _endDate = State(initialValue: defaultDate)
        _recurrence = State(initialValue: "none")
    }

    // MARK: - Init for editing an existing event
    init(existingEvent: Event, onSave: @escaping (String, String, Date, Date, String, [String]) -> Void) {
        self.defaultDate = existingEvent.startDate
        self.onSave = onSave

        _title = State(initialValue: existingEvent.title)
        _description = State(initialValue: existingEvent.description)
        _startDate = State(initialValue: existingEvent.startDate)
        _endDate = State(initialValue: existingEvent.endDate)
        _isRange = State(initialValue: !Calendar.current.isDate(existingEvent.startDate, inSameDayAs: existingEvent.endDate))
        _isRecurring = State(initialValue: existingEvent.recurrence != "none")
        _recurrence = State(initialValue: existingEvent.recurrence)
        // Prepopulate selected friends if the event already has invited friends
        _selectedFriends = State(initialValue: existingEvent.invitedFriends.filter { !$0.contains("-creator-user-") }
            .map { Friend(username: $0) })    }

    var body: some View {
        NavigationView {
            Form {
                // Event detail fields
                Section(header: Text("Event Details").foregroundColor(adaptiveTextColor)) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
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
                        VStack(spacing: 0) {
                            Divider()
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(friendVM.friends.map { Friend(username: $0) }
                                        .filter { !$0.id.contains("-creator-user-") }
                                    ) { friend in
                                        if !selectedFriends.contains(friend) {
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
                            }
                            .frame(maxHeight: 150)
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

                // Notifications
                Section(header: Text("Reminders").foregroundColor(adaptiveTextColor)) {
                    ForEach(reminderOptions) { opt in
                        Toggle(isOn: Binding<Bool>(
                            get: { selectedReminders.contains(opt.id) },
                            set: { isOn in
                                if isOn { selectedReminders.insert(opt.id) }
                                else { selectedReminders.remove(opt.id) }
                            }
                        )) {
                            Text(opt.label)
                        }
                        .tint(adaptiveTextColor)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { hideKeyboard() }
            .onAppear { requestNotificationPermission() }
            .tint(adaptiveTextColor)
            .navigationBarTitle("Add Event", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let finalEndDate = isRange ? endDate : startDate
                    scheduleRemindersIfNeeded(eventTitle: title, start: startDate)
                    // Pass the selected friend IDs along with other parameters.
                    onSave(title, description, startDate, finalEndDate, recurrence, selectedFriends.map { $0.id })
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
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

    func scheduleRemindersIfNeeded(eventTitle: String, start: Date) {
        let center = UNUserNotificationCenter.current()
        let selectedOpts = reminderOptions.filter { selectedReminders.contains($0.id) }
        guard !selectedOpts.isEmpty else { return }

        for opt in selectedOpts {
            let triggerDate = start.addingTimeInterval(-opt.secondsBefore)
            if triggerDate < Date() { continue } // skip past reminders

            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let content = UNMutableNotificationContent()
            content.title = "Upcoming Event"
            content.body = "\(eventTitle.isEmpty ? "Event" : eventTitle) starts soon."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
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
