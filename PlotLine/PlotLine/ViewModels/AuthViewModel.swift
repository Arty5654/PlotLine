//
//  AuthViewModel.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/5/25.
//

import SwiftUI

class AuthViewModel: ObservableObject {
 
    @Published var isLoggedIn: Bool = false

    init() {
        //TODO load from UserDefaults to ensure a user stays logged in til signout
    }

    func signIn() {
            // TODO add auth logic once backend is integrated
            
        self.isLoggedIn = true
    }

    func signOut() {
        // TODO update
        
        self.isLoggedIn = false
    }
    

}

