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

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootView()
                    .environmentObject(session)
                    .environmentObject(calendarVM)
                    .environmentObject(friendsVM)
                    .environmentObject(chatVM)
                    .onOpenURL { url in
                        GIDSignIn.sharedInstance.handle(url)
                    }
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? ""
            guard !username.isEmpty else { return }
            calendarVM.fetchEvents()
            Task { await friendsVM.loadFriends(for: username) }
        }
    }
}
