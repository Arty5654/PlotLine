//
//  AuthTests.swift
//  PlotLineTests
//
//  Sign up / sign in: validation rules, phone formatting, server responses, legal links.
//

import Testing
import Foundation
@testable import PlotLine

@MainActor
struct AuthTests {

    @Test("Password rules match what the server expects")
    func passwordRules() {
        func passes(_ pw: String) -> Bool { AuthViewModel.passwordRules.allSatisfy { $0.isMet(pw) } }
        #expect(passes("Password1"))
        #expect(!passes("password1"))   // no uppercase
        #expect(!passes("PASSWORD1"))   // no lowercase
        #expect(!passes("Password"))    // no number
        #expect(!passes("Pass1"))       // too short
        #expect(AuthViewModel.passwordRules.count == 4)
    }

    @Test("Usernames are letters and numbers only")
    func usernames() {
        let vm = AuthViewModel()
        #expect(vm.isValidUsername("alex2026"))
        #expect(!vm.isValidUsername("alex 2026"))
        #expect(!vm.isValidUsername("alex/../bob"))
        #expect(!vm.isValidUsername("alex_2026"))
        #expect(!vm.isValidUsername(""))
    }

    @Test("Email format check")
    func emails() {
        let vm = AuthViewModel()
        #expect(vm.isValidEmail("me@example.com"))
        #expect(vm.isValidEmail("First.Last+tag@school.edu"))
        #expect(!vm.isValidEmail("me@example"))
        #expect(!vm.isValidEmail("not an email"))
    }

    @Test("Phone numbers display as (555) 555-0123 as you type")
    func phoneFormatting() {
        #expect(SignUpView.formatUSPhone("") == "")
        #expect(SignUpView.formatUSPhone("555") == "555")
        #expect(SignUpView.formatUSPhone("55555") == "(555) 55")
        #expect(SignUpView.formatUSPhone("5555550123") == "(555) 555-0123")
        #expect(SignUpView.formatUSPhone("(555) 555-0123") == "(555) 555-0123")
    }

    @Test("Sign-in response with terms and verification status decodes")
    func authResponse() throws {
        let full = try TestJSON.decode(AuthResponse.self,
            #"{"success":true,"token":"abc","error":"Needs Verification","displayUsername":"Alex","needsTerms":true}"#)
        #expect(full.success)
        #expect(full.token == "abc")
        #expect(full.error == "Needs Verification")
        #expect(full.needsTerms == true)

        // older servers don't send needsTerms
        let minimal = try TestJSON.decode(AuthResponse.self, #"{"success":false,"error":"Incorrect Password"}"#)
        #expect(minimal.needsTerms == nil)
        #expect(minimal.token == nil)
    }

    @Test("Sign-up request carries the terms agreement")
    func signUpRequest() throws {
        let body = try TestJSON.object(SignUpRequest(phone: "5555550123", email: "a@b.com", username: "alex",
                                                     password: "Password1", acceptedTerms: true))
        #expect(body["acceptedTerms"] as? Bool == true)
        #expect(body["phone"] as? String == "5555550123")
    }

    @Test("Username message matches the server's wording, so the setup sheet can show it inline")
    func usernameRulesWording() {
        #expect(AuthViewModel.usernameRules == "Usernames must be 3 to 30 letters or numbers.")
    }

    @Test("Google sign-in sends no username until a new user picks one")
    func googleRequest() throws {
        let first = try TestJSON.object(GoogleSignInRequest(idToken: "t", username: nil, email: "a@gmail.com"))
        #expect(first["username"] == nil)
        let chosen = try TestJSON.object(GoogleSignInRequest(idToken: "t", username: "johnny", email: "a@gmail.com"))
        #expect(chosen["username"] as? String == "johnny")
    }

    @Test("Too many attempts: the server's try-again message is shown as-is")
    func rateLimitMessage() throws {
        let url = URL(string: "https://example.com/auth/signin")!
        let limited = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "420"])!
        let body = Data(#"{"success":false,"error":"Too many attempts. Try again in 7 minutes."}"#.utf8)
        let error = try #require(AuthAPI.rateLimited(body, limited))
        #expect(AuthViewModel.message(for: error) == "Too many attempts. Try again in 7 minutes.")

        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        #expect(AuthAPI.rateLimited(body, ok) == nil)
    }

    @Test("Daily AI limit shows the server's message")
    func aiLimitMessage() throws {
        let url = URL(string: "https://example.com/api/llm/budget")!
        let limited = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil)!
        let body = Data(#"{"success":false,"error":"You've reached today's limit for AI features. Try again in 3 hours."}"#.utf8)
        let error = try #require(AILimitError.from(body, limited))
        #expect(error.localizedDescription == "You've reached today's limit for AI features. Try again in 3 hours.")

        // a 429 without a readable body still explains itself
        #expect(AILimitError.from(nil, limited)?.message.contains("today's limit") == true)

        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        #expect(AILimitError.from(body, ok) == nil)
        let serverError = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        #expect(AILimitError.from(body, serverError) == nil)
    }

    @Test("Error messages shown to users")
    func errorMessages() {
        #expect(AuthViewModel.message(for: AuthError.custom("Incorrect Password")) == "Incorrect Password")
        #expect(AuthViewModel.message(for: AuthError.sessionExpired).contains("sign in again"))
        #expect(AuthViewModel.message(for: AuthError.serverError).contains("Server error"))
    }

    @Test("Terms and privacy links point at the backend")
    func legalLinks() {
        #expect(LegalPage.terms.url.path == "/terms")
        #expect(LegalPage.privacy.url.path == "/privacy")
        #expect(LegalPage.terms.url.host == LegalPage.privacy.url.host)
    }
}
