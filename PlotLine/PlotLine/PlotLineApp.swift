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

        // Tab bar: white background in dark mode so icons are visible; system default in light mode
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .systemBackground
        }

        let selectedColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .systemBlue : .systemBlue
        }
        let normalColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .systemGray : .systemGray
        }

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
            NavigationStack {
                RootView()
                    .environmentObject(session)
                    .environmentObject(calendarVM)
                    .environmentObject(friendsVM)
                    .environmentObject(chatVM)
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
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
            guard !username.isEmpty else { return }
            WidgetDataWriter.writeCredentials()
            WidgetDataWriter.refreshFinancialData()
            WidgetDataWriter.refreshGoalsData()
            calendarVM.fetchEvents()
            Task { await friendsVM.loadFriends(for: username) }
        }
    }
}

extension NSNotification.Name {
    static let plotlineDeepLink = NSNotification.Name("PlotLineDeepLink")
}
