//
//  AuthViewModel.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/5/25.
//

import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
 
    @Published var isLoggedIn: Bool = false
    @Published var errorMessage: String?
    @Published var authToken: String?
    
    @Published var isSignin: Bool = false

    init() {
        if let token = KeychainManager.loadToken() {
            self.authToken = token
            self.isLoggedIn = true
        } else {
            self.isLoggedIn = false
        }
    }
    
    func signUp(phone: String, username: String, password: String, confPassword: String) {
        // clear prev error
        self.errorMessage = nil
        
        // null error checks
        guard !phone.isEmpty, !username.isEmpty, !password.isEmpty, !confPassword.isEmpty else {
            self.errorMessage = "Please fill out all fields."
            return
        }
        
        //password error checks
        if password != confPassword {
            self.errorMessage = "Please ensure passwords match."
            return
        }
        guard password.count >= 8 else {
            self.errorMessage = "Password must be 8 digits"
            return
        }
        guard password.rangeOfCharacter(from: .decimalDigits) != nil, password.rangeOfCharacter(from: .uppercaseLetters) != nil, password.rangeOfCharacter(from: .lowercaseLetters) != nil else {
            
            self.errorMessage = "Password requires an uppercase, lowercase, and a number."
            return
        }
        
        //username errorchecks (no spaces or special characters)
        guard isValidUsername(username) else {
            self.errorMessage = "Username can only contain letters and numbers."
            return
        }
        
        Task {
            do {
                let response = try await AuthAPI.signUp(
                    phone: phone,
                    username: username,
                    password: password
                )
                
                // On success
                if let token = response.token {
                    KeychainManager.saveToken(token)
                }
                self.authToken = response.token
                self.isLoggedIn = true
                print("User Logged in!")
                
            } catch {
                // Handle errors from AuthAPI
                if let authError = error as? AuthError {
                    switch authError {
                    case .custom(let msg):
                        self.errorMessage = msg
                    case .invalidURL:
                        self.errorMessage = "Invalid URL"
                    case .serverError:
                        self.errorMessage = "Server error."
                    }
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.isLoggedIn = false
            }
        }
        
    }

    func signIn(username: String, password: String) {
        
        Task {
            do {
                let response = try await AuthAPI.signIn(
                    username: username,
                    password: password
                )
                
                // On success
                if let token = response.token {
                    KeychainManager.saveToken(token)
                }
                self.authToken = response.token
                self.isLoggedIn = true
                print("User Logged in!")
                
            } catch {
                // Handle errors from AuthAPI
                if let authError = error as? AuthError {
                    switch authError {
                    case .custom(let msg):
                        self.errorMessage = msg
                    case .invalidURL:
                        self.errorMessage = "Invalid URL"
                    case .serverError:
                        self.errorMessage = "Server error."
                    }
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.isLoggedIn = false
            }
        }

    }

    func signOut() {
        // TODO update
        
        self.isLoggedIn = false
        self.authToken = nil
        KeychainManager.removeToken()
    }
    
    // regex check for valid username (alphanumeric only)
    func isValidUsername(_ username: String) -> Bool {
        let regex = "^[a-zA-Z0-9]+$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: username)
    }
    

}

