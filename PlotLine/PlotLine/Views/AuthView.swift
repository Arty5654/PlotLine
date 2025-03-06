//
//  AuthView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/13/25.
//
import SwiftUI

struct AuthView: View {
    
    @EnvironmentObject var session: AuthViewModel
    
    var body: some View {
        if session.isSignin {
            SignInView()
                .environmentObject(session)
        } else {
            SignUpView()
                .environmentObject(session)
        }
    }
}

#Preview {
   AuthView()
        .environmentObject(AuthViewModel())
}

