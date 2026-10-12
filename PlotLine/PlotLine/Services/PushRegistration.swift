//
//  PushRegistration.swift
//  PlotLine
//
//  Push notifications from the server (friend requests, invites, chat replies, the Sunday budget
//  recap) go to the phones registered here. A phone is registered once notifications are allowed
//  and someone is signed in; signing out removes it.
//

import UIKit
import UserNotifications

enum PushRegistration {

    private static let tokenKey = "pushDeviceToken"

    /// ask iPhone for this phone's push address (the answer arrives in the AppDelegate)
    @MainActor
    static func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// at launch and when the app comes back: keeps the server's copy (and time zone) current
    static func refreshIfAllowed() {
        Task {
            guard UserDefaults.standard.string(forKey: "loggedInUsername")?.isEmpty == false,
                  NotificationPermission.isAllowed(await NotificationPermission.status()) else { return }
            await register()
        }
    }

    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// iPhone gave us the address: tell the server it belongs to whoever is signed in
    static func didRegister(token: Data) {
        let hexToken = hex(token)
        UserDefaults.standard.set(hexToken, forKey: tokenKey)
        guard UserDefaults.standard.string(forKey: "loggedInUsername")?.isEmpty == false,
              let url = URL(string: "\(BackendConfig.baseURLString)/api/push/devices") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        BackendConfig.addApiKey(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        #if DEBUG
        let environment = "sandbox"      // builds run from Xcode use Apple's test push servers
        #else
        let environment = "production"   // TestFlight and the App Store
        #endif
        request.httpBody = try? JSONEncoder().encode([
            "token": hexToken, "environment": environment, "timeZone": TimeZone.current.identifier,
        ])
        Task { _ = try? await URLSession.shared.data(for: request) } // retried at the next launch
    }

    /// Signing out: this phone stops getting that account's notifications. Built while still signed
    /// in (the request needs the login), then sent.
    static func unregisterRequest() -> URLRequest? {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              var components = URLComponents(string: "\(BackendConfig.baseURLString)/api/push/devices") else { return nil }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        BackendConfig.addApiKey(to: &request)
        request.timeoutInterval = 5
        return request
    }
}
