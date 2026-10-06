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
