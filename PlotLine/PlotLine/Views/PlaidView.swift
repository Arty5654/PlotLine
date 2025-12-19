//
//  PlaidView.swift
//  PlotLine
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

struct PlaidView: View {
    @StateObject private var linkCoordinator = PlaidLinkCoordinator()

    var body: some View {
        Button {
            Task { await link() }
        } label: {
            Label("Link a card or bank", systemImage: "link")
        }
        .buttonStyle(.borderedProminent)
    }

    private func link() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/link_token?username=\(currentUsername())"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let linkToken = obj["link_token"] as? String
        else { print("Failed to fetch link_token"); return }

        await presentPlaidLink(linkToken: linkToken, coordinator: linkCoordinator) { publicToken, accountIds in
            Task { await exchange(publicToken: publicToken, selectedAccountIds: accountIds) }
        }
    }

    private func syncPlaid() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/sync?username=\(currentUsername())") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: req)
    }

    private func exchange(publicToken: String, selectedAccountIds: [String]) async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/exchange") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "username": currentUsername(),
            "public_token": publicToken,
            "account_ids": selectedAccountIds
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)

        await MainActor.run { linkCoordinator.handler = nil }
    }


    private func currentUsername() -> String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
}

// MARK: - Presentation helpers

@MainActor
func presentPlaidLink(
    linkToken: String,
    coordinator: PlaidLinkCoordinator,
    onSuccess: @escaping (_ publicToken: String, _ selectedAccountIds: [String]) -> Void
) async {
    var config = LinkTokenConfiguration(token: linkToken) { success in
        // Grab selected account ids from Link metadata
        let accountIds = success.metadata.accounts.map { $0.id }
        onSuccess(success.publicToken, accountIds)
    }
    config.onExit = { exit in print("Plaid exited: \(exit)") }

    switch Plaid.create(config) {
    case .failure(let error):
        print("Plaid create failed: \(error)")
    case .success(let handler):
        coordinator.handler = handler
        guard let host = topViewController() else { return }
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

#Preview { PlaidView() }
