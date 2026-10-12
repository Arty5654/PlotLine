//
//  TrophyAlerts.swift
//  PlotLine
//
//  "Trophy earned! Gold · Meal Prepper" slides in at the top of whatever screen you're on.
//
//  Most trophies are awarded by the server as a side effect (making a grocery list, saving a goal,
//  analyzing a food photo), so the app compares trophy levels with the last ones it saw: after
//  requests to the server (a few times over the next ~40 s, since AI features finish late) and when
//  the app opens. The first check on a device only records the levels, so old trophies don't pop up.
//

import SwiftUI
import UIKit

@MainActor
final class TrophyAlerts: ObservableObject {
    static let shared = TrophyAlerts()

    struct Award: Identifiable, Equatable {
        let id = UUID()
        let trophyId: String
        let name: String
        let description: String
        let level: Int
    }

    @Published private(set) var current: Award?
    private var queue: [Award] = []
    private var window: UIWindow?
    private var hideTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?

    private init() { }

    // MARK: - Checking

    /// A request to the server was made: anything might have earned a trophy. Trophy requests
    /// themselves don't count (the check is one, and an increment answers with the trophies).
    nonisolated static func requestMade(to url: URL?) {
        let path = url?.path ?? ""
        guard !path.contains("get-trophies"), !path.contains("increment-trophies") else { return }
        Task { @MainActor in shared.scheduleChecks() }
    }

    /// the app opened: show anything earned in the background, and check
    func appBecameActive() {
        if current == nil { showNext() }
        Task { await check() }
    }

    private func scheduleChecks() {
        checkTask?.cancel() // more requests: start the schedule over
        checkTask = Task {
            var waited = 0
            for at in [2, 12, 40] {
                try? await Task.sleep(for: .seconds(at - waited))
                waited = at
                guard !Task.isCancelled else { return }
                await check()
            }
        }
    }

    private func check() async {
        guard let username = Self.username,
              let trophies = try? await ProfileAPI.fetchTrophies(username: username) else { return }
        update(trophies, username: username)
    }

    /// new levels in `trophies` pop up; called with any fresh trophy list
    func update(_ trophies: [Trophy], username: String) {
        guard username == Self.username else { return } // signed out meanwhile
        let key = "trophyLevelsSeen.\(username.lowercased())"
        let seen = UserDefaults.standard.dictionary(forKey: key) as? [String: Int]
        let awards = Self.newAwards(trophies, seen: seen)
        UserDefaults.standard.set(Dictionary(trophies.map { ($0.id, $0.level) }, uniquingKeysWith: max), forKey: key)
        guard !awards.isEmpty else { return }
        queue.append(contentsOf: awards)
        // earned during background work: shown when the app is opened
        if current == nil, UIApplication.shared.applicationState == .active { showNext() }
    }

    /// levels higher than last seen. Nothing seen yet on this device: none (it's the starting point).
    nonisolated static func newAwards(_ trophies: [Trophy], seen: [String: Int]?) -> [Award] {
        guard let seen else { return [] }
        return trophies
            .filter { $0.level > (seen[$0.id] ?? 0) }
            .map { Award(trophyId: $0.id, name: $0.name, description: $0.description, level: $0.level) }
    }

    private nonisolated static var username: String? {
        let name = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
        return name.isEmpty ? nil : name
    }

    // MARK: - Showing

    private func showNext() {
        guard !queue.isEmpty else { return }
        let award = queue.removeFirst()
        installWindow()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { current = award }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement,
                             argument: "Trophy earned: \(Trophy.levelName(award.level)) \(award.name)")
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { current = nil }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if queue.isEmpty {
                if current == nil { window?.isHidden = true }
            } else {
                showNext()
            }
        }
    }

    // a window just tall enough for the card, above sheets and alerts, so the rest of the screen keeps working
    private func installWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        let topInset = scene.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 47
        let frame = CGRect(x: 0, y: 0, width: scene.screen.bounds.width, height: topInset + 120)

        if window == nil || window?.windowScene !== scene {
            let cardWindow = UIWindow(windowScene: scene)
            cardWindow.windowLevel = .alert + 2 // above the error banner
            cardWindow.backgroundColor = .clear
            let host = UIHostingController(rootView: TrophyAlertView(alerts: self))
            host.view.backgroundColor = .clear
            cardWindow.rootViewController = host
            window = cardWindow
        }
        window?.frame = frame
        window?.isHidden = false
    }
}

extension Trophy {
    static func levelName(_ level: Int) -> String {
        switch level {
        case 1: return "Bronze"
        case 2: return "Silver"
        case 3: return "Gold"
        case 4: return "Diamond"
        default: return ""
        }
    }

    static func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color(red: 205/255, green: 127/255, blue: 50/255)
        case 2: return .gray
        case 3: return .yellow
        case 4: return .mint
        default: return .primary
        }
    }

    static func imageName(id: String, level: Int) -> String {
        if id == "llm-investor" { return "llmTrophy" }
        if id == "first-profile-picture" { return "profilePicTrophy" }
        switch level {
        case 2: return "silverTrophy"
        case 3: return "goldTrophy"
        case 4: return "diamondTrophy"
        default: return "bronzeTrophy"
        }
    }

    /// one-time trophies (a first profile picture) have a single level: no "Diamond" for them
    static func isOneTime(_ id: String) -> Bool {
        ["all-around", "llm-investor", "first-profile-picture", "getting-started"].contains(id)
    }
}

struct TrophyAlertView: View {
    @ObservedObject var alerts: TrophyAlerts

    var body: some View {
        VStack {
            if let award = alerts.current {
                card(award)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(award.id)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    private func card(_ award: TrophyAlerts.Award) -> some View {
        let color = Trophy.levelColor(award.level)
        let oneTime = Trophy.isOneTime(award.trophyId)
        return HStack(spacing: 12) {
            Image(Trophy.imageName(id: award.trophyId, level: award.level))
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(oneTime ? "Trophy earned!" : "\(Trophy.levelName(award.level)) trophy earned!")
                    .font(.caption.weight(.bold))
                    .foregroundColor(oneTime ? PLColor.tint : award.level == 3 ? Color(red: 0.8, green: 0.6, blue: 0) : color) // yellow text is hard to read on white
                    .textCase(.uppercase)
                Text(award.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(award.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button { alerts.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke((oneTime ? PLColor.tint : color).opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { alerts.dismiss() }
        .gesture(DragGesture(minimumDistance: 10).onEnded { value in
            if value.translation.height < 0 { alerts.dismiss() } // swipe up to dismiss
        })
        .accessibilityElement(children: .combine)
    }
}
