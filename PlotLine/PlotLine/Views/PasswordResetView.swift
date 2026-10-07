//
//  PasswordResetView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/24/25.
//

import SwiftUI

struct PasswordResetView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var rawPhone: String = ""      // 10 digits; the backend adds +1
    @State private var code: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    @State private var isCodeSent = false
    @State private var isWorking = false
    @State private var didReset = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?
    enum Field { case username, phone, code, password, confirm }

    private var canSendCode: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && rawPhone.count == 10
    }
    private var passwordValid: Bool { AuthViewModel.passwordRules.allSatisfy { $0.isMet(newPassword) } }
    private var passwordsMatch: Bool { !confirmPassword.isEmpty && newPassword == confirmPassword }
    private var canReset: Bool { code.count >= 4 && passwordValid && passwordsMatch }

    var body: some View {
        ScrollView {
            VStack(spacing: AuthStyle.spacing) {
                AuthHero(title: "Reset your password",
                         subtitle: isCodeSent
                            ? "Enter the code we texted you and choose a new password."
                            : "We'll text a code to the phone number on your account.",
                         logoSize: 64)
                    .padding(.top, 8)

                if didReset {
                    AuthMessage(text: "Password updated. You can sign in with your new password.", kind: .success)
                } else if isCodeSent {
                    resetStep
                } else {
                    requestStep
                }
            }
            .padding(.horizontal, AuthStyle.spacing)
            .padding(.bottom, AuthStyle.spacing)
            .animation(.easeInOut(duration: 0.2), value: isCodeSent)
            .animation(.easeOut(duration: 0.2), value: errorMessage)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: Step 1: who are you

    private var requestStep: some View {
        VStack(spacing: 12) {
            AuthField(icon: "person", placeholder: "Username", text: $username,
                      focus: $focusedField, field: .username, contentType: .username,
                      onSubmit: { focusedField = .phone })

            AuthField(icon: "phone", placeholder: "Phone number on your account", text: phoneBinding,
                      focus: $focusedField, field: .phone,
                      contentType: .telephoneNumber, keyboard: .numberPad,
                      isInvalid: !rawPhone.isEmpty && rawPhone.count != 10)

            if let errorMessage { AuthMessage(text: errorMessage) }

            AuthPrimaryButton(title: "Send Code", isLoading: isWorking, isEnabled: canSendCode,
                              action: requestPasswordReset)
        }
        .authCard()
        .transition(.opacity)
    }

    // MARK: Step 2: code + new password

    private var resetStep: some View {
        VStack(spacing: 12) {
            AuthField(icon: "number", placeholder: "6-digit code", text: codeBinding,
                      focus: $focusedField, field: .code,
                      contentType: .oneTimeCode, keyboard: .numberPad)

            AuthField(icon: "lock", placeholder: "New password", text: $newPassword,
                      focus: $focusedField, field: .password,
                      isSecure: true, contentType: .newPassword,
                      onSubmit: { focusedField = .confirm })

            PasswordChecklist(password: newPassword)

            AuthField(icon: "lock.rotation", placeholder: "Confirm new password", text: $confirmPassword,
                      focus: $focusedField, field: .confirm,
                      isSecure: true, contentType: .newPassword, submitLabel: .go,
                      isInvalid: !confirmPassword.isEmpty && !passwordsMatch,
                      trailing: passwordsMatch
                        ? AnyView(Image(systemName: "checkmark.circle.fill").foregroundColor(AuthStyle.success))
                        : nil,
                      onSubmit: resetPassword)

            if let errorMessage { AuthMessage(text: errorMessage) }

            AuthPrimaryButton(title: "Reset Password", isLoading: isWorking, isEnabled: canReset,
                              action: resetPassword)

            Button("Change info and resend") {
                isCodeSent = false
                code = ""
                newPassword = ""
                confirmPassword = ""
                errorMessage = nil
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(AuthStyle.accent)
        }
        .authCard()
        .transition(.opacity)
    }

    private var phoneBinding: Binding<String> {
        Binding(get: { SignUpView.formatUSPhone(rawPhone) },
                set: { rawPhone = String($0.filter(\.isNumber).prefix(10)) })
    }

    private var codeBinding: Binding<String> {
        Binding(get: { code }, set: { code = String($0.filter(\.isNumber).prefix(6)) })
    }

    private func requestPasswordReset() {
        guard canSendCode, !isWorking else { return }
        focusedField = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await AuthAPI.sendCode(phone: rawPhone)
                isCodeSent = true
                errorMessage = nil
                focusedField = .code
            } catch AuthError.custom(let message) where message.hasPrefix("Too many") {
                errorMessage = message
            } catch {
                errorMessage = "Couldn't send a code. Check your details and try again."
            }
        }
    }

    private func resetPassword() {
        guard canReset, !isWorking else { return }
        focusedField = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let success = try await AuthAPI.changePasswordWithCode(
                    username: username.trimmingCharacters(in: .whitespaces),
                    newPassword: newPassword, code: code)
                if success {
                    errorMessage = nil
                    didReset = true
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    dismiss()
                } else {
                    errorMessage = "Invalid code or failed to reset."
                }
            } catch {
                errorMessage = AuthViewModel.message(for: error)
            }
        }
    }
}

struct PasswordResetView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { PasswordResetView() }
    }
}
