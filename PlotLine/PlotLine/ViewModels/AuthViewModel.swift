//
//  AuthViewModel.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/5/25.
//

import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices
import CryptoKit

@MainActor
class AuthViewModel: ObservableObject {
 
    @Published var isLoggedIn: Bool = false
    
    @Published var signupErrorMessage: String?
    @Published var loginErrorMessage: String?
    @Published var verificationErrorMessage: String?
    
    @Published var authToken: String?
    
    @Published var isSignin: Bool = false
    // pending setup steps are saved so closing and reopening the app can't skip them
    // (the server enforces them too)
    @Published var needVerification: Bool? {
        didSet { UserDefaults.standard.set(needVerification == true, forKey: Self.pendingPhoneKey) }
    }
    
    @Published var phoneNumber: String = ""
    @Published var isCodeSent: Bool = false
    
    @Published var trophies: [Trophy] = []
    
    @Published var signOutPending: Bool = false

    // true while a sign in / sign up / Google request is running (drives button spinners)
    @Published var isAuthenticating: Bool = false
    // true while an SMS code is being sent or checked
    @Published var phoneStepInFlight: Bool = false

    // Terms of Service: true until the signed-in user accepts the current version
    @Published var needsTermsAcceptance: Bool = false {
        didSet { UserDefaults.standard.set(needsTermsAcceptance, forKey: Self.pendingTermsKey) }
    }
    private static let pendingPhoneKey = "pendingPhoneVerification"
    private static let pendingTermsKey = "pendingTermsAcceptance"
    @Published var termsInFlight: Bool = false
    @Published var termsErrorMessage: String?

    // account deletion
    @Published var deleteAccountInFlight: Bool = false
    @Published var deleteAccountErrorMessage: String?
    @Published var deleteNeedsAppleConfirmation: Bool = false
    @Published var deleteNeedsFreshSignIn: Bool = false

    // password rules, shared by the sign-up checklist and validation
    struct PasswordRule: Identifiable {
        let id: String
        let isMet: (String) -> Bool
    }
    static let passwordRules: [PasswordRule] = [
        PasswordRule(id: "8+ characters") { $0.count >= 8 },
        PasswordRule(id: "Uppercase letter") { $0.rangeOfCharacter(from: .uppercaseLetters) != nil },
        PasswordRule(id: "Lowercase letter") { $0.rangeOfCharacter(from: .lowercaseLetters) != nil },
        PasswordRule(id: "Number") { $0.rangeOfCharacter(from: .decimalDigits) != nil },
    ]

    // Sign in with Apple follow-up (new account needs a username, or an existing account needs its password)
    enum AppleAccountStep: Identifiable, Equatable {
        case chooseUsername(suggested: String)
        case linkAccount(existingUsername: String)

        var id: String {
            switch self {
            case .chooseUsername: return "chooseUsername"
            case .linkAccount: return "linkAccount"
            }
        }
    }
    @Published var appleAccountStep: AppleAccountStep?
    @Published var appleStepErrorMessage: String?
    @Published var appleStepInFlight: Bool = false

    private struct PendingAppleSignIn {
        let identityToken: String
        let rawNonce: String
        let userID: String
        let suggestedUsername: String
    }
    private var pendingApple: PendingAppleSignIn?
    private var currentAppleNonce: String?
    private static let appleUserIDKey = "appleUserID"

    init() {
        if let token = KeychainManager.loadToken() {
            self.authToken = token
            self.isLoggedIn = true
            // pick up where a previous launch left off; refreshSession() then confirms with the server
            if UserDefaults.standard.bool(forKey: Self.pendingPhoneKey) { self.needVerification = true }
            self.needsTermsAcceptance = UserDefaults.standard.bool(forKey: Self.pendingTermsKey)
            signOutIfAppleCredentialRevoked()
            refreshSession()
        } else {
            self.isLoggedIn = false
        }
    }
    
    func signUp(phone: String, email: String, username: String, password: String, confPassword: String, agreedToTerms: Bool) {
        // clear prev error
        self.signupErrorMessage = nil

        guard agreedToTerms else {
            self.signupErrorMessage = "Please confirm you're 18 or older and agree to the Terms of Service and Privacy Policy."
            return
        }
        
        // null error checks
        guard !phone.isEmpty, !email.isEmpty, !username.isEmpty, !password.isEmpty, !confPassword.isEmpty else {
            self.signupErrorMessage = "Please fill out all fields."
            return
        }
        
        guard isValidEmail(email) else {
            self.signupErrorMessage = "Enter a valid email."
            return
        }
        
        //password error checks
        if password != confPassword {
            self.signupErrorMessage = "Please ensure passwords match."
            return
        }
        guard Self.passwordRules.allSatisfy({ $0.isMet(password) }) else {
            self.signupErrorMessage = "Password needs 8+ characters with an uppercase letter, a lowercase letter, and a number."
            return
        }
        
        //username errorchecks (no spaces or special characters)
        guard isValidUsername(username) else {
            self.signupErrorMessage = "Username can only contain letters and numbers."
            return
        }
        
        isAuthenticating = true
        Task {
            defer { self.isAuthenticating = false }
            do {
                let response = try await AuthAPI.signUp(
                    phone: phone,
                    email: email,
                    username: username,
                    password: password,
                    acceptedTerms: agreedToTerms
                )
                
                // On success
                if let token = response.token {
                    KeychainManager.saveToken(token)
                    // Save username so we can connect data to the user in different views
                    // Use displayUsername from server (original case) or fall back to typed username
                    let usernameToStore = response.displayUsername ?? username
                    UserDefaults.standard.set(usernameToStore, forKey: "loggedInUsername")
                    self.phoneNumber = phone
                }
                self.authToken = response.token
                self.needsTermsAcceptance = response.needsTerms ?? false
                self.isLoggedIn = true
                self.signupErrorMessage = nil

                // trigger phone verification
                if response.error == "Needs Verification" {
                    self.needVerification = true
                }

            } catch {
                self.signupErrorMessage = Self.message(for: error)
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
            
            Task { @MainActor in
                self.isAuthenticating = true
                defer { self.isAuthenticating = false }
                do {
                    let response = try await AuthAPI.googleSignIn(idToken: idToken, username: username!, email: email!)
                    //TODO make this use username instead of email
                    
                    if let token = response.token {
                        KeychainManager.saveToken(token)
                        // Use displayUsername from server (original case) or fall back to typed username
                        let usernameToStore = response.displayUsername ?? username
                        UserDefaults.standard.set(usernameToStore, forKey: "loggedInUsername")

                        self.authToken = token

                        self.needsTermsAcceptance = response.needsTerms ?? false
                        self.isLoggedIn = true

                        // trigger phone verification
                        if response.error == "Needs Verification" {
                            self.needVerification = true
                        }
                    }
                } catch {
                    self.loginErrorMessage = Self.message(for: error)
                    self.signupErrorMessage = Self.message(for: error)
                }
            }

            
        }
        
        
    }

    // MARK: - Sign in with Apple

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        self.signupErrorMessage = nil
        self.loginErrorMessage = nil

        // Apple signs sha256(nonce) into the identity token; the backend checks it against the raw nonce
        let nonce = Self.randomNonce()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            self.signupErrorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
            self.loginErrorMessage = "Apple Sign-In failed: \(error.localizedDescription)"

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = currentAppleNonce else {
                self.signupErrorMessage = "Apple Sign-In: Identity token not found"
                self.loginErrorMessage = "Apple Sign-In: Identity token not found"
                return
            }

            // Apple only shares the name on the very first sign-in, so it may be empty
            let suggestedUsername = (credential.fullName?.givenName ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber) }

            pendingApple = PendingAppleSignIn(identityToken: identityToken,
                                              rawNonce: rawNonce,
                                              userID: credential.user,
                                              suggestedUsername: suggestedUsername)
            Task { await submitAppleSignIn(username: nil, linkPassword: nil) }
        }
    }

    func submitAppleUsername(_ username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard isValidUsername(trimmed) else {
            self.appleStepErrorMessage = "Username can only contain letters and numbers."
            return
        }
        Task { await submitAppleSignIn(username: trimmed, linkPassword: nil) }
    }

    func submitAppleLinkPassword(_ password: String) {
        guard !password.isEmpty else {
            self.appleStepErrorMessage = "Please enter your password."
            return
        }
        Task { await submitAppleSignIn(username: nil, linkPassword: password) }
    }

    func cancelAppleSignIn() {
        pendingApple = nil
        appleAccountStep = nil
        appleStepErrorMessage = nil
    }

    private func submitAppleSignIn(username: String?, linkPassword: String?) async {
        guard let pending = pendingApple, !appleStepInFlight else { return }
        appleStepInFlight = true
        appleStepErrorMessage = nil
        defer { appleStepInFlight = false }

        do {
            let response = try await AuthAPI.appleSignIn(identityToken: pending.identityToken,
                                                         rawNonce: pending.rawNonce,
                                                         username: username,
                                                         linkPassword: linkPassword)

            if response.success, let token = response.token {
                KeychainManager.saveToken(token)
                UserDefaults.standard.set(response.displayUsername ?? username, forKey: "loggedInUsername")
                UserDefaults.standard.set(pending.userID, forKey: Self.appleUserIDKey)
                self.authToken = token
                cancelAppleSignIn()

                // trigger phone verification
                if response.error == "Needs Verification" {
                    self.needVerification = true
                }
                self.needsTermsAcceptance = response.needsTerms ?? false
                self.isLoggedIn = true
                return
            }

            switch response.error {
            case AuthAPI.appleUsernameRequired:
                self.appleAccountStep = .chooseUsername(suggested: pending.suggestedUsername)
            case AuthAPI.appleLinkRequired:
                self.appleAccountStep = .linkAccount(existingUsername: response.displayUsername ?? "")
            default:
                break
            }
        } catch {
            let message = Self.message(for: error)

            // wrong password / taken username can be fixed in the sheet; anything else means start over
            let fixableInSheet = message == "Incorrect Password" || message == "Username already taken"
                || message == "Username can only contain letters and numbers."
            if appleAccountStep != nil && fixableInSheet {
                self.appleStepErrorMessage = message
            } else {
                cancelAppleSignIn()
                self.signupErrorMessage = message
                self.loginErrorMessage = message
            }
        }
    }

    // MARK: - Session

    private var isRefreshingSession = false

    // Swap the login token for a fresh one (called at launch and whenever the app comes back),
    // so people stay signed in as long as they open the app at least every 30 days.
    func refreshSession() {
        guard KeychainManager.loadToken() != nil, !isRefreshingSession else { return }
        isRefreshingSession = true
        Task {
            defer { self.isRefreshingSession = false }
            do {
                let response = try await AuthAPI.refreshSession()
                self.needsTermsAcceptance = response.needsTerms ?? false
                self.needVerification = response.error == "Needs Verification" ? true : nil
                if let token = response.token {
                    KeychainManager.saveToken(token)
                    self.authToken = token
                    if let display = response.displayUsername {
                        UserDefaults.standard.set(display, forKey: "loggedInUsername")
                    }
                }
            } catch AuthError.sessionExpired {
                self.signOut()
                self.loginErrorMessage = "Your session expired. Please sign in again."
            } catch {
                // offline or server hiccup: keep the current session and try again next time
            }
        }
    }

    func acceptTerms() {
        guard !termsInFlight else { return }
        termsErrorMessage = nil
        termsInFlight = true
        Task {
            defer { self.termsInFlight = false }
            do {
                try await AuthAPI.acceptTerms()
                self.needsTermsAcceptance = false
            } catch AuthError.sessionExpired {
                self.signOut()
                self.loginErrorMessage = "Your session expired. Please sign in again."
            } catch {
                self.termsErrorMessage = Self.message(for: error)
            }
        }
    }

    // Apple recommends checking this at launch: the user can stop using Apple ID with the app in Settings
    private func signOutIfAppleCredentialRevoked() {
        guard let appleUserID = UserDefaults.standard.string(forKey: Self.appleUserIDKey) else { return }
        Task {
            let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID)
            if state == .revoked { signOut() }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        // 64 characters so each random byte maps evenly
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate nonce")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func signIn(username: String, password: String) {
    
        self.loginErrorMessage = nil
        
        isAuthenticating = true
        Task {
            defer { self.isAuthenticating = false }
            do {
                let response = try await AuthAPI.signIn(
                    username: username,
                    password: password
                )
                
    
                // Use displayUsername from server (original case) or fall back to typed username
                let usernameToStore = response.displayUsername ?? username

                // edge case where user still hasnt verified
                if response.error == "Needs Verification" {
                    self.needVerification = true
                    self.needsTermsAcceptance = response.needsTerms ?? false
                    self.isLoggedIn = true
                    self.loginErrorMessage = nil

                    if let token = response.token {
                        KeychainManager.saveToken(token)
                        // Save username so we can connect data to the user in different views
                        UserDefaults.standard.set(usernameToStore, forKey: "loggedInUsername")
                    }
                    self.authToken = response.token

                    return
                }

                // On success
                if let token = response.token {
                    KeychainManager.saveToken(token)
                    // Save username so we can connect data to the user in different views
                    UserDefaults.standard.set(usernameToStore, forKey: "loggedInUsername")
                }
                self.authToken = response.token
                self.needsTermsAcceptance = response.needsTerms ?? false
                self.isLoggedIn = true
                self.loginErrorMessage = nil

                if response.error == "Needs Verification" {
                    self.needVerification = true
                }
                
            } catch {
                
                self.loginErrorMessage = Self.message(for: error)
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
        
        phoneStepInFlight = true
        Task {
            defer { self.phoneStepInFlight = false }
            do {
                let response = try await AuthAPI.sendCode(
                    phone: phone
                )
                self.phoneNumber = phone
                if response.success {
                    self.isCodeSent = true
                }
                
            } catch {
                self.verificationErrorMessage = "Couldn't send the code. Check the number and try again."
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
        
        phoneStepInFlight = true
        Task {
            defer { self.phoneStepInFlight = false }
            do {
                let response = try await AuthAPI.sendVerification(phone: phone, code: code, username: username)
                self.phoneNumber = phone
                if response.success {
                    self.needVerification = false
                }
                
            } catch is AuthError {
                self.verificationErrorMessage = "That code is incorrect or expired. Tap Resend to get a new one."
            } catch {
                self.verificationErrorMessage = "An unexpected error occurred. Please try again"
            }
            
            
        }
    }

    func signOut() {        
        self.isLoggedIn = false
        self.authToken = nil
        KeychainManager.removeToken()
        UserDefaults.standard.removeObject(forKey: "loggedInUsername")
        UserDefaults.standard.removeObject(forKey: Self.appleUserIDKey)
        WidgetDataWriter.clearCredentials()
        BadgeManager.clear()
        
        self.isCodeSent = false
        self.isSignin = true
        self.phoneNumber = ""
        self.needVerification = nil
        self.needsTermsAcceptance = false
        self.termsErrorMessage = nil
    }
    
    // regex check for valid username (alphanumeric only)
    func isValidUsername(_ username: String) -> Bool {
        let regex = "^[a-zA-Z0-9]+$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: username)
    }
    
    // MARK: - Delete account

    func deleteAccount(appleAuthorizationCode: String? = nil) {
        guard !deleteAccountInFlight else { return }
        deleteAccountErrorMessage = nil
        deleteNeedsFreshSignIn = false
        deleteAccountInFlight = true

        Task {
            defer { self.deleteAccountInFlight = false }
            do {
                let response = try await AuthAPI.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
                if response.error == AuthAPI.appleAuthorizationRequired {
                    // Apple accounts confirm with Apple once more so the server can revoke Apple's access
                    self.deleteNeedsAppleConfirmation = true
                    return
                }
                self.deleteNeedsAppleConfirmation = false
                self.wipeLocalData()
                self.signOut()
            } catch AuthError.sessionExpired {
                self.deleteNeedsFreshSignIn = true
                self.deleteAccountErrorMessage = "For your security, please sign in again, then delete your account."
            } catch {
                self.deleteAccountErrorMessage = Self.message(for: error)
            }
        }
    }

    func prepareAppleDeleteConfirmation(_ request: ASAuthorizationAppleIDRequest) {
        deleteAccountErrorMessage = nil
        request.requestedScopes = []
    }

    func handleAppleDeleteConfirmation(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            deleteAccountErrorMessage = "Apple confirmation failed: \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let codeData = credential.authorizationCode,
                  let code = String(data: codeData, encoding: .utf8) else {
                deleteAccountErrorMessage = "Apple confirmation failed. Please try again."
                return
            }
            deleteAccount(appleAuthorizationCode: code)
        }
    }

    // remove everything this account left on the device
    private func wipeLocalData() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        let appGroupID = "group.com.ArteomAvetissian.PlotLine.shared"
        UserDefaults(suiteName: appGroupID)?.removePersistentDomain(forName: appGroupID)
        WidgetDataWriter.reloadWidgets()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        // also drops the app's Google access (calendar import etc.) if a Google session exists
        if GIDSignIn.sharedInstance.currentUser != nil {
            GIDSignIn.sharedInstance.disconnect { _ in }
        }
    }

    static func message(for error: Error) -> String {
        guard let authError = error as? AuthError else { return error.localizedDescription }
        switch authError {
        case .custom(let msg): return msg
        case .invalidURL: return "Invalid URL"
        case .serverError: return "Server error. Please try again."
        case .sessionExpired: return "Your session expired. Please sign in again."
        }
    }

    func isValidEmail(_ email: String) -> Bool {
        let regex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        return NSPredicate(format: "SELF MATCHES[c] %@", regex).evaluate(with: email)
    }
    
    //fetch trophies
    func loadTrophies(for username: String) async {
        do {
            let trophies = try await ProfileAPI.fetchTrophies(username: username)
            self.trophies = trophies
        } catch {
            print("Failed to fetch trophies: \(error)")
        }
    }

}
