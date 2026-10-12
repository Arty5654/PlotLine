//
//  PlotLineApp.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/4/25.
//

import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

@main
struct PlotLineApp: App {

    @StateObject private var session = AuthViewModel()
    @StateObject var calendarVM = CalendarViewModel()
    @StateObject var friendsVM = FriendsViewModel()
    @StateObject var chatVM = ChatViewModel()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Navigation bar back button and bar button items: white in dark mode, system blue in light mode
        let adaptiveNavColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .systemBlue
        }
        UINavigationBar.appearance().tintColor = adaptiveNavColor

        // Tab bar: the system background (dark in dark mode), blue for the selected tab, gray for the rest
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = .systemBackground

        let selectedColor = UIColor.systemBlue
        let normalColor = UIColor.systemGray

        for layout in [tabAppearance.stackedLayoutAppearance,
                       tabAppearance.inlineLayoutAppearance,
                       tabAppearance.compactInlineLayoutAppearance] {
            layout.selected.iconColor = selectedColor
            layout.selected.titleTextAttributes = [.foregroundColor: selectedColor]
            layout.normal.iconColor = normalColor
            layout.normal.titleTextAttributes = [.foregroundColor: normalColor]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .background(KeyboardDismisser())
                .environmentObject(session)
                .environmentObject(calendarVM)
                .environmentObject(friendsVM)
                .environmentObject(chatVM)
                // opening the app with the lock on asks for Face ID right away (scene changes can
                // start before this view is watching them)
                .onAppear { AppLock.shared.sceneChanged(to: .active) }
                // keep the widgets' copy of the login token current (sign-in, refresh)
                .onChange(of: session.authToken) { _, token in
                    if token != nil { WidgetDataWriter.writeCredentials() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .plotlineSessionRejected)) { _ in
                    session.refreshSession()
                }
                .onOpenURL { url in
                    if url.scheme == "plotline" {
                        var userInfo: [String: Any] = ["destination": url.host ?? ""]
                        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                            for item in items { userInfo[item.name] = item.value ?? "" }
                        }
                        NotificationCenter.default.post(name: .plotlineDeepLink, object: nil, userInfo: userInfo)
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            AppLock.shared.sceneChanged(to: phase) // Face ID lock and the app-switcher cover
            // the icon is visible again once the app is in the background: recount what's waiting
            if phase == .background {
                BadgeManager.refreshInBackground()
                return
            }
            guard phase == .active else { return }
            session.refreshSession()
            // a membership can end, renew or be refunded while the app is closed
            if session.isLoggedIn && !session.needsTermsAcceptance && session.needVerification != true {
                Task { await MembershipManager.shared.refresh() }
            }
            let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
            guard !username.isEmpty else { return }
            WidgetDataWriter.writeCredentials()
            WidgetDataWriter.refreshFinancialData()
            WidgetDataWriter.refreshGoalsData()
            calendarVM.fetchEvents(quiet: true) // background refresh: errors show when they open the calendar
            calendarVM.syncAppleCalendarIfConnected()
            Task { await friendsVM.loadFriends(for: username) }
            TrophyAlerts.shared.appBecameActive()
            PushRegistration.refreshIfAllowed() // keeps this phone's push address and time zone current
        }
    }
}

extension NSNotification.Name {
    static let plotlineDeepLink = NSNotification.Name("PlotLineDeepLink")
}
