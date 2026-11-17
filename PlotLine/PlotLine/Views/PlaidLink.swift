//
//  PlaidLink.swift
//  PlotLine
//  Opening Plaid Link to connect a bank (used by Budget), and the "Plaid synced" notification.
//
//  Created by Arteom Avetissian on 10/11/25.
//

import SwiftUI
import LinkKit
import UIKit

// Keep a strong ref to the Link handler for the lifetime of the flow
final class PlaidLinkCoordinator: ObservableObject {
    @Published var handler: Handler?
}

// MARK: - Presentation helpers

@MainActor
func presentPlaidLink(
    linkToken: String,
    coordinator: PlaidLinkCoordinator,
    onSuccess: @escaping (_ publicToken: String, _ selectedAccountIds: [String]) -> Void
) async {
    // signing in to the bank there can use Face ID AutoFill: the app lock shouldn't cover it
    var config = LinkTokenConfiguration(token: linkToken) { success in
        Task { @MainActor in AppLock.shared.passwordScreenDisappeared() }
        // Grab selected account ids from Link metadata
        let accountIds = success.metadata.accounts.map { $0.id }
        onSuccess(success.publicToken, accountIds)
    }
    config.onExit = { exit in
        Task { @MainActor in AppLock.shared.passwordScreenDisappeared() }
        print("Plaid exited: \(exit)")
    }

    switch Plaid.create(config) {
    case .failure(let error):
        print("Plaid create failed: \(error)")
    case .success(let handler):
        coordinator.handler = handler
        guard let host = topViewController() else { return }
        AppLock.shared.passwordScreenAppeared()
        handler.open(presentUsing: .viewController(host))
    }
}

// Find a host UIViewController for presentation
private func topViewController(_ root: UIViewController? = nil) -> UIViewController? {
    let rootVC: UIViewController? = {
        if let root { return root }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let win = scene.windows.first(where: { $0.isKeyWindow })
        else { return nil }
        return win.rootViewController
    }()

    if let nav = rootVC as? UINavigationController {
        return topViewController(nav.visibleViewController)
    }
    if let tab = rootVC as? UITabBarController, let sel = tab.selectedViewController {
        return topViewController(sel)
    }
    if let presented = rootVC?.presentedViewController {
        return topViewController(presented)
    }
    return rootVC
}

extension Notification.Name {
    static let plaidSynced = Notification.Name("PlaidSynced")
}


/// Connecting a bank: gets a link token, opens Plaid, and saves the bank on the server.
/// Used by Budget and by the budget quiz.
@MainActor
final class BankLinker: ObservableObject {
    @Published private(set) var isLinking = false
    private let coordinator = PlaidLinkCoordinator()

    private var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }

    /// `onLinked` runs once the bank is saved (not when Plaid is closed without linking)
    func link(onLinked: @escaping () -> Void = {}) async {
        guard !isLinking else { return }
        isLinking = true
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/link_token?username=\(username)") else {
            isLinking = false
            return
        }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let linkToken = obj["link_token"] as? String else {
                isLinking = false
                AppBanner.report("start connecting your bank", AILimitError.from(data, response) ?? URLError(.badServerResponse))
                return
            }
            await presentPlaidLink(linkToken: linkToken, coordinator: coordinator) { [weak self] publicToken, accountIds in
                Task { await self?.exchange(publicToken: publicToken, accountIds: accountIds, onLinked: onLinked) }
            }
            isLinking = false
        } catch {
            isLinking = false
            AppBanner.report("start connecting your bank", error)
        }
    }

    private func exchange(publicToken: String, accountIds: [String], onLinked: @escaping () -> Void) async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/exchange") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": username, "public_token": publicToken, "account_ids": accountIds,
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if !AppBanner.reportIfFailed("finish connecting your bank", data, response, nil) { onLinked() }
        } catch {
            AppBanner.report("finish connecting your bank", error)
        }
        coordinator.handler = nil
    }
}
