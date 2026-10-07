//
//  MembershipManager.swift
//  PlotLine
//
//  PlotLine is subscription-only: without an active membership the app shows the paywall
//  (RootView). The server decides and also enforces it (402 "Membership Required"). The last
//  answer is remembered so the right screen shows straight away on the next launch.
//

import Foundation
import Combine

@MainActor
final class MembershipManager: ObservableObject {
    static let shared = MembershipManager()

    enum Access: String {
        case unknown, unlocked, locked
    }

    @Published private(set) var access: Access
    @Published private(set) var status: MembershipStatus?
    /// the server's reason it couldn't use this Apple ID's subscription (e.g. used by another account)
    @Published private(set) var purchaseProblem: String?
    /// the last check failed (offline), so the loading screen offers a retry
    @Published private(set) var checkFailed = false

    private static let accessKey = "membershipAccess"
    private var expiryCheck: Task<Void, Never>?

    private init() {
        access = Access(rawValue: UserDefaults.standard.string(forKey: Self.accessKey) ?? "") ?? .unknown
    }

    /// Asks the server. If the account is locked but this Apple ID has a subscription (e.g. a
    /// renewal the server hasn't heard about), sends it first.
    func refresh() async {
        guard KeychainManager.loadToken() != nil,
              let username = UserDefaults.standard.string(forKey: "loggedInUsername"), !username.isEmpty else { return }
        do {
            var status = try await PaymentAPI.fetchStatus(username: username)
            if !status.active {
                do {
                    if let synced = try await StoreKitManager.shared.syncCurrentEntitlements() { status = synced }
                } catch PaymentAPIError.custom(let message) {
                    purchaseProblem = message
                } catch {
                    print("Couldn't send App Store subscription: \(error)")
                }
            }
            update(status)
        } catch {
            checkFailed = true
        }
    }

    func update(_ status: MembershipStatus) {
        self.status = status
        checkFailed = false
        if status.active { purchaseProblem = nil }
        access = status.active ? .unlocked : .locked
        UserDefaults.standard.set(access.rawValue, forKey: Self.accessKey)
        scheduleExpiryCheck(status)
    }

    // if the app is left open when the free week (or a subscription) runs out, check again then
    private func scheduleExpiryCheck(_ status: MembershipStatus) {
        expiryCheck?.cancel()
        guard status.active, let end = status.expiresDate else { return }
        let wait = end.timeIntervalSinceNow + 5
        guard wait > 0, wait < 8 * 86_400 else { return }
        expiryCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// sign out: the next account checks from scratch
    func reset() {
        expiryCheck?.cancel()
        status = nil
        purchaseProblem = nil
        checkFailed = false
        access = .unknown
        UserDefaults.standard.removeObject(forKey: Self.accessKey)
    }
}
