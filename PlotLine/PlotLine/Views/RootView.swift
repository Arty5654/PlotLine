//
//  RootView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/5/25.
//

import SwiftUI



struct RootView: View {
    
    @EnvironmentObject var session: AuthViewModel
    @EnvironmentObject var calendarVM: CalendarViewModel
    @EnvironmentObject var friendsVM : FriendsViewModel
    
    var body: some View {
        if session.isLoggedIn && session.needVerification != true {
            ContentView()
                .environmentObject(session)
                .environmentObject(calendarVM)
                .environmentObject(friendsVM)
        } else if (session.needVerification == true) {
            PhoneVerificationView()
                .environmentObject(session)
        } else {
            // No auth, signin page display
            AuthView()
                .environmentObject(session)
        }
        
        
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
}
