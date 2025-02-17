//
//  RootView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/5/25.
//

import SwiftUI



struct RootView: View {
    
    @EnvironmentObject var session: AuthViewModel
    // TODO replace ContentView() with home screen
    
    var body: some View {
        if session.isLoggedIn {
            ContentView()
                .environmentObject(session)
        } else {
            // No auth, signin page display
            AuthView()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
}
