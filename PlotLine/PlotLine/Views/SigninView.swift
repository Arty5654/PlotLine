import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

// MARK: - Lightweight design tokens (scoped to this file)
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
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(tint.opacity(configuration.isPressed ? 0.6 : 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

// MARK: - Field wrapper
private struct LabeledField<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundColor(PLColor.textSecondary)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
            }
            content()
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PLColor.cardBorder))
        }
    }
}

// MARK: - Main View
struct SignInView: View {
    // Env
    @EnvironmentObject var session: AuthViewModel

    // State
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword = false

    @FocusState private var focusedField: Field?
    enum Field { case username, password }

    // Derived
    private var canSubmit: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PLSpacing.lg) {
                    // Logo + title
                    VStack(spacing: PLSpacing.sm) {
                        Image("PlotLineLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 108, height: 108)
                            .shadow(radius: 6, y: 2)

                        Text("PlotLine")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(PLColor.accent)
                            .padding(.top, 2)
                    }
                    .padding(.top, 12)

                    // Card with fields
                    VStack(spacing: PLSpacing.md) {
                        LabeledField(title: "Username", systemImage: "person") {
                            TextField("Enter your username", text: $username)
                                .textInputAutocapitalization(.none)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }

                        LabeledField(title: "Password", systemImage: "lock") {
                            HStack {
                                if showPassword {
                                    TextField("Enter your password", text: $password)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .focused($focusedField, equals: .password)
                                        .submitLabel(.go)
                                        .onSubmit { if canSubmit { session.signIn(username: username, password: password) } }
                                } else {
                                    SecureField("Enter your password", text: $password)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .focused($focusedField, equals: .password)
                                        .submitLabel(.go)
                                        .onSubmit { if canSubmit { session.signIn(username: username, password: password) } }
                                }
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(PLColor.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Error (if any)
                        if let error = session.loginErrorMessage, !error.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.footnote)
                            .foregroundColor(PLColor.danger)
                            .padding(.top, 2)
                        }

                        // Sign in
                        Button {
                            session.signIn(username: username, password: password)
                        } label: {
                            Text("Sign In")
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

                    // Google
                    GoogleSignInButton(action: { session.googleSignIn() })
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .plCard()

                    // Help links
                    HStack {
                        NavigationLink(destination: PasswordResetView()) {
                            Text("Forgot password?")
                                .foregroundColor(PLColor.accent)
                        }
                        Spacer()
                        Button {
                            session.isSignin = false
                            session.loginErrorMessage = nil
                            session.signupErrorMessage = nil
                        } label: {
                            Text("No account? Sign up")
                                .foregroundColor(.green)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.bottom, PLSpacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text("Welcome").font(.headline) } }
            .onTapGesture { hideKeyboard() }
        }
    }

    // Dismiss keyboard helper
    private func hideKeyboard() {
        focusedField = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - Preview
struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.light)
    }
}
