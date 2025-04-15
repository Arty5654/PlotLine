import SwiftUI

struct AddEventSheet: View {
    @Environment(\.presentationMode) var presentationMode
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
        _selectedFriends = State(initialValue: existingEvent.invitedFriends.map { Friend(username: $0) })
    }

    var body: some View {
        NavigationView {
            Form {
                // Event detail fields
                Section(header: Text("Event Details")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                }

                // Date selection fields
                Section(header: Text("Dates")) {
                    Toggle("Multiple Days?", isOn: $isRange)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)

                    if isRange {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }

                // Recurrence options
                Section(header: Text("Repeat")) {
                    Toggle("Recurring Event?", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Frequency", selection: $recurrence) {
                            Text("Never (Default)").tag("none")
                            Text("Every Week").tag("weekly")
                            Text("Every other week").tag("biweekly")
                            Text("Every Month").tag("monthly")
                        }
                    }
                }


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
                        VStack(spacing: 0) {
                            Divider()
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(friendVM.friends.map { Friend(username: $0) }) { friend in
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
                                                        .foregroundColor(.blue)
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
            }
            .navigationBarTitle("Add Event", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let finalEndDate = isRange ? endDate : startDate
                    // Pass the selected friend IDs along with other parameters.
                    onSave(title, description, startDate, finalEndDate, recurrence, selectedFriends.map { $0.id })
                    presentationMode.wrappedValue.dismiss()
                }
            )
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

