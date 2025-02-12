//
//  PlotLineApp.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/4/25.
//

import SwiftUI

@main
struct PlotLineApp: App {
    
    @StateObject private var session = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootView()
                    .environmentObject(session)
            }

        }
    }
}
