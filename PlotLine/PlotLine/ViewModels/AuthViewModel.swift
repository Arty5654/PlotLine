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
    
    @Published var signupErrorMessage: String?
    @Published var loginErrorMessage: String?
    
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
        self.signupErrorMessage = nil
        
        // null error checks
        guard !phone.isEmpty, !username.isEmpty, !password.isEmpty, !confPassword.isEmpty else {
            self.signupErrorMessage = "Please fill out all fields."
            return
        }
        
        //password error checks
        if password != confPassword {
            self.signupErrorMessage = "Please ensure passwords match."
            return
        }
        guard password.count >= 8 else {
            self.signupErrorMessage = "Password must be 8 digits"
            return
        }
        guard password.rangeOfCharacter(from: .decimalDigits) != nil, password.rangeOfCharacter(from: .uppercaseLetters) != nil, password.rangeOfCharacter(from: .lowercaseLetters) != nil else {
            
            self.signupErrorMessage = "Password requires an uppercase, lowercase, and a number."
            return
        }
        
        //username errorchecks (no spaces or special characters)
        guard isValidUsername(username) else {
            self.signupErrorMessage = "Username can only contain letters and numbers."
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
                self.signupErrorMessage = nil
                print("User Logged in!")
                
            } catch {
                // Handle errors from AuthAPI
                if let authError = error as? AuthError {
                    switch authError {
                    case .custom(let msg):
                        self.signupErrorMessage = msg
                    case .invalidURL:
                        self.signupErrorMessage = "Invalid URL"
                    case .serverError:
                        self.signupErrorMessage = "Server error."
                    }
                } else {
                    self.signupErrorMessage = error.localizedDescription
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
                self.loginErrorMessage = nil
                
            } catch {
                // Handle errors from AuthAPI
                if let authError = error as? AuthError {
                    switch authError {
                    case .custom(let msg):
                        self.loginErrorMessage = msg
                    case .invalidURL:
                        self.loginErrorMessage = "Invalid URL"
                    case .serverError:
                        self.loginErrorMessage = "Server error."
                    }
                } else {
                    self.loginErrorMessage = error.localizedDescription
                }
                self.isLoggedIn = false
            }
        }

    }

    func signOut() {        
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

