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
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
    }

    func signIn() {
            // TODO add auth logic once backend is integrated
            
        self.isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
    }

    func signOut() {
        // TODO update
        
        self.isLoggedIn = false
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
    }
    

}

