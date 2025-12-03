import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

// MARK: - Lightweight tokens (scoped)
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let success        = Color.green
    static let danger         = Color.red
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius { static let md: CGFloat = 12 }

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.lg)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.success.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
private struct OutlineButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(tint))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
private struct LabeledField<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundColor(PLColor.textSecondary)
                Text(title).font(.subheadline).foregroundColor(PLColor.textSecondary)
            }
            content()
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PLColor.cardBorder))
        }
    }
}

// MARK: - View
struct SignUpView: View {
    // Env
    @EnvironmentObject var session: AuthViewModel

    // State
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var rawPhone: String = ""        
    @State private var password: String = ""
    @State private var confPassword: String = ""
    @State private var showPassword = false
    @State private var showConfPassword = false

    @FocusState private var focusedField: Field?
    enum Field { case phone, username, password, confPassword }

    // Derived
    private var formattedPhone: String {
        formatUSPhone(rawPhone)
    }

    // Show error only after user types something
    private var usernameError: String? {
        guard !username.isEmpty else { return nil }
        return username.trimmingCharacters(in: .whitespaces).count >= 3
            ? nil
            : "Username must be at least 3 characters."
    }

    private var phoneError: String? {
        guard !rawPhone.isEmpty else { return nil }
        return rawPhone.count == 10
            ? nil
            : "Enter a valid 10-digit US phone number."
    }
    
    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: email.utf16.count)
        let match = regex?.firstMatch(in: email, options: [], range: range)
        return match != nil ? nil : "Enter a valid email address."
    }

    private var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 8 ? nil : "Password must be at least 8 characters."
    }
    private var matchError: String? {
        guard !confPassword.isEmpty else { return nil }
        return password == confPassword ? nil : "Passwords don’t match."
    }
    private var localErrorMessage: String? {
        // show the first local validation error (order matters)
        phoneError ?? usernameError ?? passwordError ?? matchError
    }
    private var canSubmit: Bool {
        phoneError == nil &&
        emailError == nil &&
        usernameError == nil &&
        passwordError == nil &&
        matchError == nil &&
        !username.isEmpty && !email.isEmpty && !password.isEmpty && !confPassword.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PLSpacing.lg) {
                    // Branding
                    VStack(spacing: PLSpacing.sm) {
                        Image("PlotLineLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 108, height: 108)
                            .shadow(radius: 6, y: 2)
                        Text("Create your account")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(PLColor.accent)
                    }
                    .padding(.top, 12)

                    // Card with fields
                    VStack(spacing: PLSpacing.md) {
                        // Phone
                        LabeledField(title: "Phone Number", systemImage: "phone") {
                            TextField("(555) 555-5555", text: Binding(
                                get: { formattedPhone },
                                set: { new in
                                    // keep only digits and clamp to 10
                                    rawPhone = new.filter(\.isNumber)
                                    if rawPhone.count > 10 { rawPhone = String(rawPhone.prefix(10)) }
                                }
                            ))
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .phone)
                        }
                        if let err = phoneError {
                            FieldError(text: err)
                        }

                        // Username
                        LabeledField(title: "Username", systemImage: "person") {
                            TextField("Choose a username", text: $username)
                                .textInputAutocapitalization(.none)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }
                        if let err = usernameError {
                            FieldError(text: err)
                        }
                        
                        // Email
                        LabeledField(title: "Email", systemImage: "envelope") {
                            TextField("you@example.com", text: $email)
                                .textInputAutocapitalization(.none)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .submitLabel(.next)
                        }
                        if let err = emailError {
                            FieldError(text: err)
                        }

                        // Password
                        LabeledField(title: "Password", systemImage: "lock") {
                            HStack {
                                if showPassword {
                                    TextField("At least 8 characters", text: $password)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .focused($focusedField, equals: .password)
                                        .submitLabel(.next)
                                } else {
                                    SecureField("At least 8 characters", text: $password)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .focused($focusedField, equals: .password)
                                        .submitLabel(.next)
                                }
                                Button { showPassword.toggle() } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(PLColor.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let err = passwordError {
                            FieldError(text: err)
                        }

                        // Confirm Password
                        LabeledField(title: "Confirm Password", systemImage: "lock") {
                            HStack {
                                if showConfPassword {
                                    TextField("Re-enter password", text: $confPassword)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .focused($focusedField, equals: .confPassword)
                                        .submitLabel(.go)
                                        .onSubmit { submitIfPossible() }
                                } else {
                                    SecureField("Re-enter password", text: $confPassword)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .focused($focusedField, equals: .confPassword)
                                        .submitLabel(.go)
                                        .onSubmit { submitIfPossible() }
                                }
                                Button { showConfPassword.toggle() } label: {
                                    Image(systemName: showConfPassword ? "eye.slash" : "eye")
                                        .foregroundColor(PLColor.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let err = matchError {
                            FieldError(text: err)
                        }

                        // Backend error (if any)
                        if let be = session.signupErrorMessage, !be.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(be).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.footnote)
                            .foregroundColor(PLColor.danger)
                            .padding(.top, 4)
                        }

                        // Submit
                        Button {
                            session.signUp(
                                phone: rawPhone,
                                email: email.trimmingCharacters(in: .whitespaces),
                                username: username.trimmingCharacters(in: .whitespaces),
                                password: password,
                                confPassword: confPassword
                            )
                        } label: {
                            Text("Sign Up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButton())
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                    }
                    .plCard()

                    // Or divider
                    HStack {
                        Rectangle().frame(height: 1).foregroundColor(PLColor.cardBorder)
                        Text("or").foregroundColor(PLColor.textSecondary).font(.footnote)
                        Rectangle().frame(height: 1).foregroundColor(PLColor.cardBorder)
                    }

                    // Google sign-up
                    GoogleSignInButton(action: { session.googleSignIn() })
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .plCard()

                    // Login link
                    HStack {
                        Text("Already have an account?")
                            .foregroundColor(PLColor.textSecondary)
                        Button {
                            session.isSignin = true
                            session.loginErrorMessage = nil
                            session.signupErrorMessage = nil
                        } label: {
                            Text("Log in")
                                .foregroundColor(.green)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.bottom, PLSpacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text("Sign Up").font(.headline) } }
            .onTapGesture { hideKeyboard() }
        }
    }

    // MARK: - Helpers
    private func submitIfPossible() {
        if canSubmit {
            session.signUp(
                phone: rawPhone,
                email: email.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                confPassword: confPassword
            )
        }
    }

    private func formatUSPhone(_ digits: String) -> String {
        let d = digits.filter(\.isNumber)
        switch d.count {
        case 0...3:
            return d
        case 4...6:
            let a = String(d.prefix(3))
            let b = String(d.dropFirst(3))
            return "(\(a)) \(b)"
        default:
            let a = String(d.prefix(3))
            let b = String(d.dropFirst(3).prefix(3))
            let c = String(d.dropFirst(6).prefix(4))
            return "(\(a)) \(b)-\(c)"
        }
    }

    private func hideKeyboard() {
        focusedField = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - Small subviews
private struct FieldError: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundColor(PLColor.danger)
        .padding(.top, 2)
    }
}

// MARK: - Preview
struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.light)
    }
}
