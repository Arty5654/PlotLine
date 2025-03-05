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
    @Published var verificationErrorMessage: String?
    
    @Published var authToken: String?
    
    @Published var isSignin: Bool = false
    @Published var needVerification: Bool?
    
    @Published var phoneNumber: String = ""
    @Published var isCodeSent: Bool = false

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
                    self.phoneNumber = phone
                }
                self.authToken = response.token
                self.isLoggedIn = true
                self.signupErrorMessage = nil
                
                // trigger phone verification
                if response.error == "Needs Verification" {
                    self.needVerification = true
                }
                
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
        self.loginErrorMessage = nil
        
        
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
                self.loginErrorMessage = "Google Sign-In: Internal Error"
                return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                self.signupErrorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                self.loginErrorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                return
            }
            
            guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                self.signupErrorMessage = "Google Sign-In: User or ID Token not found"
                self.loginErrorMessage = "Google Sign-In: User or ID Token not found"
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
                        
                        // trigger phone verification
                        if response.error == "Needs Verification" {
                            self.needVerification = true
                        }
                    }
                } catch {
                    self.loginErrorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    self.signupErrorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
            }

            
        }
        
        
    }

    func signIn(username: String, password: String) {
    
        self.loginErrorMessage = nil
        
        Task {
            do {
                let response = try await AuthAPI.signIn(
                    username: username,
                    password: password
                )
                
    
                // edge case where user still hasnt verified
                if response.error == "Needs Verification" {
                    self.needVerification = true
                    self.isLoggedIn = true
                    self.loginErrorMessage = nil
                    
                    if let token = response.token {
                        KeychainManager.saveToken(token)
                        // Save username so we can connect data to the user in different views
                        UserDefaults.standard.set(username, forKey: "loggedInUsername")
                    }
                    self.authToken = response.token
                    
                    return
                }
                
                // On success
                if let token = response.token {
                    KeychainManager.saveToken(token)
                    // Save username so we can connect data to the user in different views
                    UserDefaults.standard.set(username, forKey: "loggedInUsername")
                }
                self.authToken = response.token
                self.isLoggedIn = true
                self.loginErrorMessage = nil
                
                if response.error == "Needs Verification" {
                    self.needVerification = true
                }
                
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
    
    func sendSmsCode(phone: String) {
        
        self.verificationErrorMessage = nil
        
        guard !phone.isEmpty else {
            self.verificationErrorMessage = "Error: Phone number is empty"
            return
        }
        
        Task {
            do {
                let response = try await AuthAPI.sendCode(
                    phone: phone
                )
                self.phoneNumber = phone
                if response.success {
                    self.isCodeSent = true
                }
                
            } catch {
                self.verificationErrorMessage = error.localizedDescription
            }
            
            
        }
    }
    
    func verifyCode(phone: String, code: String, username: String) {
        
        self.verificationErrorMessage = nil
        
        guard !phone.isEmpty else {
            self.verificationErrorMessage = "Phone number is empty"
            return
        }
        
        guard !code.isEmpty else {
            self.verificationErrorMessage = "Code must not be empty"
            return
        }
        
        guard !username.isEmpty else {
            self.verificationErrorMessage = "User not found. Please sign out and try again"
            return
        }
        
        Task {
            do {
                let response = try await AuthAPI.sendVerification(phone: phone, code: code, username: username)
                self.phoneNumber = phone
                if response.success {
                    self.needVerification = false
                }
                
            } catch let authError as AuthError {
                self.verificationErrorMessage = "Incorrect or expired Code! Click below to a new one if necessary."
            } catch {
                self.verificationErrorMessage = "An unexpected error occurred. Please try again"
            }
            
            
        }
    }

    func signOut() {        
        self.isLoggedIn = false
        self.authToken = nil
        KeychainManager.removeToken()
        
        self.isCodeSent = false
        self.isSignin = true
        self.phoneNumber = ""
        self.needVerification = nil
    }
    
    // regex check for valid username (alphanumeric only)
    func isValidUsername(_ username: String) -> Bool {
        let regex = "^[a-zA-Z0-9]+$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: username)
    }
    

}

