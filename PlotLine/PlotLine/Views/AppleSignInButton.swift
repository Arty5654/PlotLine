//
//  AppleSignInButton.swift
//  PlotLine
//
import SwiftUI
import AuthenticationServices

// Sign in with Apple button, plus the sheet for the one-time follow-up
// (picking a username, or linking to an existing account with its password)
struct AppleSignInButton: View {
    @EnvironmentObject var session: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    var label: SignInWithAppleButton.Label = .signIn

    var body: some View {
        SignInWithAppleButton(label,
                              onRequest: { session.prepareAppleSignIn($0) },
                              onCompletion: { session.handleAppleSignIn($0) })
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: AuthStyle.controlHeight, maxHeight: AuthStyle.controlHeight)
            .clipShape(RoundedRectangle(cornerRadius: AuthStyle.radius))
            // the button doesn't restyle on its own when the color scheme changes
            .id(colorScheme)
            .sheet(item: $session.appleAccountStep, onDismiss: { session.cancelAppleSignIn() }) { step in
                AppleAccountSetupView(step: step)
                    .environmentObject(session)
            }
    }
}

private struct AppleAccountSetupView: View {
    @EnvironmentObject var session: AuthViewModel
    let step: AuthViewModel.AppleAccountStep

    @State private var username: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: Field?
    enum Field { case username, password }

    private var isUsernameStep: Bool {
        if case .chooseUsername = step { return true }
        return false
    }

    private var canSubmit: Bool {
        isUsernameStep ? !username.trimmingCharacters(in: .whitespaces).isEmpty : !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: isUsernameStep ? "person.crop.circle.badge.plus" : "link.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AuthStyle.accent)
                        .padding(.top, 8)

                    switch step {
                    case .chooseUsername:
                        Text("This is the name your friends will see and search for.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        AuthField(icon: "person", placeholder: "Username", text: $username,
                                  focus: $focusedField, field: .username,
                                  contentType: .username, submitLabel: .done, onSubmit: submit)
                        Text("Letters and numbers only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)

                    case .linkAccount(let existingUsername):
                        Text("Your Apple ID email already belongs to the PlotLine account **\(existingUsername)**. Enter its password once to connect Sign in with Apple.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        AuthField(icon: "lock", placeholder: "Password", text: $password,
                                  focus: $focusedField, field: .password,
                                  isSecure: true, contentType: .password, submitLabel: .go, onSubmit: submit)

                        HStack {
                            Spacer()
                            NavigationLink(destination: PasswordResetView()) {
                                Text("Forgot password?")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(AuthStyle.accent)
                            }
                        }
                    }

                    if let error = session.appleStepErrorMessage, !error.isEmpty {
                        AuthMessage(text: error)
                    }

                    AuthPrimaryButton(title: isUsernameStep ? "Continue" : "Connect Account",
                                      isLoading: session.appleStepInFlight,
                                      isEnabled: canSubmit,
                                      action: submit)
                }
                .padding(AuthStyle.spacing)
                .animation(.easeOut(duration: 0.2), value: session.appleStepErrorMessage)
            }
            .navigationTitle(isUsernameStep ? "Choose a Username" : "Connect Your Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { session.cancelAppleSignIn() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(session.appleStepInFlight)
        .onAppear {
            if case .chooseUsername(let suggested) = step {
                username = suggested
            }
            focusedField = isUsernameStep ? .username : .password
        }
    }

    private func submit() {
        guard canSubmit, !session.appleStepInFlight else { return }
        switch step {
        case .chooseUsername: session.submitAppleUsername(username)
        case .linkAccount: session.submitAppleLinkPassword(password)
        }
    }
}

#Preview {
    AppleSignInButton()
        .padding()
        .environmentObject(AuthViewModel())
}
