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

