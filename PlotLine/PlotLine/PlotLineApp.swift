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
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootView()
                    .environmentObject(session)
                    .environmentObject(calendarVM)
                    .environmentObject(friendsVM)
                    .onOpenURL { url in
                        GIDSignIn.sharedInstance.handle(url)
                    }
            }

        }
    }
}
