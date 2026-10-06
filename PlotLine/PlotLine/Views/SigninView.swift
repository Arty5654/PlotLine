import SwiftUI

// Sign-in form card (shown inside AuthView)
struct SignInView: View {
    @EnvironmentObject var session: AuthViewModel

    @State private var username: String = ""
    @State private var password: String = ""

    @FocusState private var focusedField: Field?
    enum Field { case username, password }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            AuthField(icon: "person", placeholder: "Username", text: $username,
                      focus: $focusedField, field: .username,
                      contentType: .username,
                      onSubmit: { focusedField = .password })

            AuthField(icon: "lock", placeholder: "Password", text: $password,
                      focus: $focusedField, field: .password,
                      isSecure: true, contentType: .password, submitLabel: .go,
                      onSubmit: submit)

            HStack {
                Spacer()
                NavigationLink(destination: PasswordResetView()) {
                    Text("Forgot password?")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(AuthStyle.accent)
                }
            }

            if let error = session.loginErrorMessage, !error.isEmpty {
                AuthMessage(text: error)
            }

            AuthPrimaryButton(title: "Sign In",
                              isLoading: session.isAuthenticating,
                              isEnabled: canSubmit,
                              action: submit)
        }
        .authCard()
        .animation(.easeOut(duration: 0.2), value: session.loginErrorMessage)
    }

    private func submit() {
        guard canSubmit, !session.isAuthenticating else { return }
        focusedField = nil
        session.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password)
    }
}

#Preview {
    NavigationStack {
        SignInView()
            .padding()
            .environmentObject(AuthViewModel())
    }
}
