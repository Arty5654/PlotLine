import SwiftUI
import GoogleSignIn

struct GoogleCalendarImportView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var calendarVM: CalendarViewModel

    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    @State private var state: ImportState = .idle
    @State private var fetchedEvents: [GoogleCalendarEvent] = []
    @State private var importedCount: Int = 0
    @State private var errorMessage: String? = nil
    @State private var rangeOption: RangeOption = .upcoming

    enum ImportState { case idle, loading, preview, importing, done, error, connected }
    enum RangeOption: String, CaseIterable, Identifiable {
        case upcoming = "Next 6 months"
        case all      = "Past 3 months + Next 6 months"
        case year     = "Full year ahead"
        var id: String { rawValue }

        var dateRange: (from: Date, to: Date) {
            let now = Date()
            let cal = Calendar.current
            switch self {
            case .upcoming:
                return (now, cal.date(byAdding: .month, value: 6, to: now)!)
            case .all:
                return (cal.date(byAdding: .month, value: -3, to: now)!, cal.date(byAdding: .month, value: 6, to: now)!)
            case .year:
                return (now, cal.date(byAdding: .year, value: 1, to: now)!)
            }
        }
    }

    var body: some View {
        NavigationView {
            Group {
                switch state {
                case .idle:
                    idleView
                case .loading:
                    loadingView("Fetching your Google Calendar events…")
                case .preview:
                    previewView
                case .importing:
                    loadingView("Importing \(fetchedEvents.count) events…")
                case .done:
                    doneView
                case .error:
                    errorView
                case .connected:
                    connectedView
                }
            }
            .navigationBarTitle("Google Calendar Import", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                    DispatchQueue.main.async {
                        if user != nil { state = .connected }
                    }
                }
            }
        }
        .tint(adaptiveTextColor)
    }

    // MARK: - Subviews

    private var idleView: some View {
        Form {
            Section(header: Text("Date Range").foregroundColor(adaptiveTextColor)) {
                Picker("Import range", selection: $rangeOption) {
                    ForEach(RangeOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                Text("Tap below to connect Google Calendar and preview events before importing. Existing PlotLine events won't be affected.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button(action: startFetch) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Connect & Preview Events")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(message)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewView: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(fetchedEvents.count) events found")
                            .font(.headline)
                        Text("from your Google Calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Preview").foregroundColor(adaptiveTextColor)) {
                ForEach(fetchedEvents.prefix(20), id: \.id) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline.bold())
                        Text(formatDate(event.start))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                if fetchedEvents.count > 20 {
                    Text("… and \(fetchedEvents.count - 20) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(action: startImport) {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Import \(fetchedEvents.count) Events")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("Import Complete")
                .font(.title2.bold())
            Text("\(importedCount) events added to your PlotLine calendar.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(errorMessage ?? "Something went wrong")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                state = .idle
                errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var connectedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Google Calendar Connected")
                .font(.title2.bold())
            Text("Your events sync automatically each time you open the app.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                state = .loading
                Task {
                    await calendarVM.syncGoogleCalendar()
                    await MainActor.run { state = .connected }
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Button(role: .destructive, action: {
                calendarVM.disconnectGoogleCalendar()
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Disconnect Google Calendar")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func startFetch() {
        state = .loading
        Task {
            do {
                let token: String
                if GIDSignIn.sharedInstance.currentUser != nil {
                    token = try await GoogleCalendarAPI.requestCalendarAccess()
                } else {
                    token = try await GoogleCalendarAPI.signInWithCalendarScope()
                }
                let range = rangeOption.dateRange
                let events = try await GoogleCalendarAPI.fetchEvents(accessToken: token, from: range.from, to: range.to)
                await MainActor.run {
                    fetchedEvents = events
                    state = events.isEmpty ? .done : .preview
                    importedCount = 0
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
            }
        }
    }

    private func startImport() {
        state = .importing
        Task {
            do {
                let gcalEvents = fetchedEvents.map { e in
                    Event(id: "gcal_\(e.id)", title: e.title, description: e.description,
                          startDate: e.start, endDate: e.end,
                          eventType: "user", recurrence: "none", invitedFriends: [])
                }
                // One request: backend replaces all gcal_ events atomically
                _ = try await CalendarAPI.batchSyncGcal(gcalEvents, username: calendarVM.username)
                await calendarVM.fetchEvents()
                await MainActor.run {
                    importedCount = fetchedEvents.count
                    state = .connected
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
