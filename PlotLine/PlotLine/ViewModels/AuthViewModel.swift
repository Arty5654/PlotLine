//
//  AuthViewModel.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/5/25.
//

import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

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
                    // Save username so we can connect data to the user in different views
                    UserDefaults.standard.set(username, forKey: "loggedInUsername")
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
    
    func googleSignIn() {
        
        self.signupErrorMessage = nil
        
        
        // configure google to handle signin
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            print("Google Sign-In: Missing Client ID in Info.plist")
            return
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
                self.signupErrorMessage = "Google Sign-In: Internal Error"
                return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                self.signupErrorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                return
            }
            
            guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                self.signupErrorMessage = "Google Sign-In: User or ID Token not found"
                return
            }
            
            let email = user.profile?.email ?? nil
            
            if (email == nil) {
                self.signupErrorMessage = "No email found"
                return
            }
            
            let username = email!.components(separatedBy: "@").first
            
            Task {
                do {
                    let response = try await AuthAPI.googleSignIn(idToken: idToken, username: username!)
                    //TODO make this use username instead of email
                    
                    if let token = response.token {
                        KeychainManager.saveToken(token)
                        UserDefaults.standard.set(username, forKey: "loggedInUsername")
                        self.authToken = token
                        self.isLoggedIn = true
                        print("Google Sign-In successful, token saved.")
                    }
                } catch {
                    self.signupErrorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
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
                    // Save username so we can connect data to the user in different views
                    UserDefaults.standard.set(username, forKey: "loggedInUsername")
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

