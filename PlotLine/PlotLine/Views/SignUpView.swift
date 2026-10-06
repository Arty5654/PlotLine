import SwiftUI

// Create-account form card (shown inside AuthView)
struct SignUpView: View {
    @EnvironmentObject var session: AuthViewModel

    @State private var username: String = ""
    @State private var email: String = ""
    @State private var rawPhone: String = ""
    @State private var password: String = ""
    @State private var confPassword: String = ""
    @State private var agreedToTerms = false

    @FocusState private var focusedField: Field?
    enum Field { case username, email, phone, password, confPassword }

    // MARK: Validation (only shown once the user has typed something)

    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }

    private var usernameError: String? {
        guard !username.isEmpty else { return nil }
        if !session.isValidUsername(trimmedUsername) { return "Use only letters and numbers." }
        if trimmedUsername.count < 3 { return "At least 3 characters." }
        return nil
    }

    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        return session.isValidEmail(email.trimmingCharacters(in: .whitespaces)) ? nil : "Enter a valid email address."
    }

    private var phoneError: String? {
        guard !rawPhone.isEmpty else { return nil }
        return rawPhone.count == 10 ? nil : "Enter a 10-digit US phone number."
    }

    private var passwordValid: Bool { AuthViewModel.passwordRules.allSatisfy { $0.isMet(password) } }
    private var passwordsMatch: Bool { !confPassword.isEmpty && password == confPassword }
    private var matchError: String? {
        guard !confPassword.isEmpty, password != confPassword else { return nil }
        return "Passwords don't match."
    }

    private var canSubmit: Bool {
        !username.isEmpty && usernameError == nil &&
        !email.isEmpty && emailError == nil &&
        rawPhone.count == 10 &&
        passwordValid && passwordsMatch &&
        agreedToTerms
    }

    var body: some View {
        VStack(spacing: 12) {
            AuthField(icon: "person", placeholder: "Username", text: $username,
                      focus: $focusedField, field: .username,
                      contentType: .username, isInvalid: usernameError != nil,
                      onSubmit: { focusedField = .email })
            if let usernameError { FieldHint(text: usernameError) }

            AuthField(icon: "envelope", placeholder: "Email", text: $email,
                      focus: $focusedField, field: .email,
                      contentType: .emailAddress, keyboard: .emailAddress, isInvalid: emailError != nil,
                      onSubmit: { focusedField = .phone })
            if let emailError { FieldHint(text: emailError) }

            AuthField(icon: "phone", placeholder: "Phone number", text: phoneBinding,
                      focus: $focusedField, field: .phone,
                      contentType: .telephoneNumber, keyboard: .numberPad, isInvalid: phoneError != nil)
            if let phoneError { FieldHint(text: phoneError) }

            AuthField(icon: "lock", placeholder: "Password", text: $password,
                      focus: $focusedField, field: .password,
                      isSecure: true, contentType: .newPassword,
                      onSubmit: { focusedField = .confPassword })

            if !password.isEmpty || focusedField == .password {
                PasswordChecklist(password: password)
            }

            AuthField(icon: "lock.rotation", placeholder: "Confirm password", text: $confPassword,
                      focus: $focusedField, field: .confPassword,
                      isSecure: true, contentType: .newPassword, submitLabel: .go,
                      isInvalid: matchError != nil,
                      trailing: passwordsMatch
                        ? AnyView(Image(systemName: "checkmark.circle.fill").foregroundColor(AuthStyle.success))
                        : nil,
                      onSubmit: submit)
            if let matchError { FieldHint(text: matchError) }

            TermsAgreementToggle(isOn: $agreedToTerms)
                .padding(.top, 4)

            if let error = session.signupErrorMessage, !error.isEmpty {
                AuthMessage(text: error)
            }

            AuthPrimaryButton(title: "Create Account",
                              isLoading: session.isAuthenticating,
                              isEnabled: canSubmit,
                              action: submit)

            Text("We'll text a code to verify your phone number.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
        .authCard()
        .animation(.easeOut(duration: 0.2), value: session.signupErrorMessage)
        .animation(.easeOut(duration: 0.2), value: focusedField)
    }

    // shows (555) 555-5555 while storing only the 10 digits the backend expects
    private var phoneBinding: Binding<String> {
        Binding(
            get: { Self.formatUSPhone(rawPhone) },
            set: { rawPhone = String($0.filter(\.isNumber).prefix(10)) }
        )
    }

    private func submit() {
        guard canSubmit, !session.isAuthenticating else { return }
        focusedField = nil
        session.signUp(
            phone: rawPhone,
            email: email.trimmingCharacters(in: .whitespaces),
            username: trimmedUsername,
            password: password,
            confPassword: confPassword,
            agreedToTerms: agreedToTerms
        )
    }

    static func formatUSPhone(_ digits: String) -> String {
        let d = digits.filter(\.isNumber)
        switch d.count {
        case 0...3:
            return d
        case 4...6:
            return "(\(d.prefix(3))) \(d.dropFirst(3))"
        default:
            return "(\(d.prefix(3))) \(d.dropFirst(3).prefix(3))-\(d.dropFirst(6).prefix(4))"
        }
    }
}

#Preview {
    SignUpView()
        .padding()
        .environmentObject(AuthViewModel())
}
