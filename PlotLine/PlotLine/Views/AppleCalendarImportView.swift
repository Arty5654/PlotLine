//
//  AppleCalendarImportView.swift
//  PlotLine
//
//  Link Apple Calendar: allow access, pick which of the phone's calendars to import, then they
//  sync each time the app opens. Import only; PlotLine never changes the phone's calendars.
//

import SwiftUI
import EventKit
import GoogleSignIn

struct AppleCalendarImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var calendarVM: CalendarViewModel

    private enum Screen { case intro, denied, picking, syncing, connected }

    @State private var screen: Screen = .intro
    @State private var accounts: [(account: String, calendars: [EKCalendar])] = []
    @State private var chosen: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .intro: introView
                case .denied: deniedView
                case .picking: pickingView
                case .syncing: syncingView
                case .connected: connectedView
                }
            }
            .navigationTitle("Apple Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(screen == .connected ? "Done" : "Cancel") { dismiss() }
                }
            }
            .onAppear(perform: showCurrentState)
        }
        .tint(PLColor.accent)
    }

    // MARK: - Screens

    private var introView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar")
                .font(.system(size: 60))
                .foregroundStyle(PLColor.tint)
            Text("Import from Apple Calendar")
                .font(.title2.bold())
            Text("See your Apple Calendar events in PlotLine. You choose which calendars to bring in, and PlotLine never changes them.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: askForAccess) {
                Label("Allow Calendar Access", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            Text("Calendar Access Is Off")
                .font(.title2.bold())
            Text("To import your events, turn on Full Access under Settings › PlotLine › Calendars, then come back.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: AppleCalendar.openSettings) {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // they may come straight back from Settings with access turned on
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if AppleCalendar.hasAccess { startPicking() }
        }
    }

    private var pickingView: some View {
        Form {
            ForEach(accounts, id: \.account) { group in
                Section(header: Text(group.account)) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        calendarRow(calendar)
                    }
                }
            }

            Section {
                Button(action: importChosen) {
                    Text(chosen.isEmpty ? "Choose at least one calendar" : "Import \(chosen.count) Calendar\(chosen.count == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(chosen.isEmpty)
            } footer: {
                Text("Events from a month ago to six months ahead are imported, and stay in sync each time you open PlotLine. Friends who can see your PlotLine calendar will see them too."
                     + (googleLinked ? " Your Google calendars start unticked because Google Calendar is already linked in PlotLine." : ""))
            }
        }
    }

    private func calendarRow(_ calendar: EKCalendar) -> some View {
        let isOn = chosen.contains(calendar.calendarIdentifier)
        return Button {
            if isOn { chosen.remove(calendar.calendarIdentifier) } else { chosen.insert(calendar.calendarIdentifier) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? PLColor.tint : Color.secondary)
                    .font(.title3)
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var syncingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Importing your events…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectedView: some View {
        let count = AppleCalendar.selectedCalendarIDs(for: calendarVM.username).count
        return VStack(spacing: 20) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Apple Calendar Connected")
                .font(.title2.bold())
            Text("\(count) calendar\(count == 1 ? "" : "s") imported. Your events sync each time you open the app.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                screen = .syncing
                Task {
                    await calendarVM.syncAppleCalendar()
                    screen = .connected
                }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())

            Button(action: startPicking) {
                Label("Choose Calendars", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButton(tint: PLColor.tint))

            Button(role: .destructive) {
                calendarVM.disconnectAppleCalendar()
                dismiss()
            } label: {
                Label("Disconnect Apple Calendar", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButton(tint: .red))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    // Google Calendar linked in PlotLine (not just signed in with Google)
    private var googleLinked: Bool {
        GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(GoogleCalendarAPI.calendarScope) == true
    }

    private func showCurrentState() {
        if AppleCalendar.isConnected(for: calendarVM.username) {
            screen = .connected
        } else if AppleCalendar.hasAccess {
            startPicking()
        } else if AppleCalendar.accessDenied {
            screen = .denied
        } else {
            screen = .intro
        }
    }

    private func askForAccess() {
        Task {
            let granted = (try? await AppleCalendar.requestAccess()) ?? false
            if granted { startPicking() } else { screen = .denied }
        }
    }

    // previously chosen calendars stay ticked; the first time, the sensible defaults are
    private func startPicking() {
        accounts = AppleCalendar.calendarsByAccount()
        let saved = AppleCalendar.selectedCalendarIDs(for: calendarVM.username)
        let all = accounts.flatMap(\.calendars)
        if saved.isEmpty {
            chosen = Set(all.filter { AppleCalendar.isOnByDefault($0, googleLinked: googleLinked) }.map(\.calendarIdentifier))
        } else {
            chosen = saved.intersection(all.map(\.calendarIdentifier))
        }
        screen = .picking
    }

    private func importChosen() {
        AppleCalendar.setSelectedCalendarIDs(chosen, for: calendarVM.username)
        screen = .syncing
        Task {
            await calendarVM.syncAppleCalendar()
            screen = .connected
        }
    }
}
