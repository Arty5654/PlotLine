//
//  ChangePasswordView.swift
//  PlotLine
//
//  Profile → Change Password. One form, one button: prove it's you with your current password
//  (or, if you forgot it, a code texted to your phone), then choose a new password. The new one has
//  to be different from the current one.
//

import SwiftUI

struct ChangePasswordModalView: View {
    @Binding var isPresented: Bool

    enum Proof { case currentPassword, textCode }

    @State private var proof: Proof = .currentPassword
    @State private var currentPassword = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    @State private var phone: String?          // 10 digits, loaded when a code is first needed
    @State private var codeSent = false
    @State private var isSendingCode = false
    @State private var isSaving = false
    @State private var didChange = false
    @State private var errorMessage: String?

    private var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }

    init(isPresented: Binding<Bool>, proof: Proof = .currentPassword) {
        _isPresented = isPresented
        _proof = State(initialValue: proof)
    }

    // MARK: - Rules

    private var passwordValid: Bool { AuthViewModel.passwordRules.allSatisfy { $0.isMet(newPassword) } }
    private var sameAsCurrent: Bool { proof == .currentPassword && !newPassword.isEmpty && newPassword == currentPassword }
    private var mismatch: Bool { !confirmPassword.isEmpty && newPassword != confirmPassword }
    private var proofGiven: Bool { proof == .currentPassword ? !currentPassword.isEmpty : code.count == 6 }

    private var canSave: Bool {
        proofGiven && passwordValid && !sameAsCurrent && !confirmPassword.isEmpty && !mismatch && !isSaving
    }

    /// what's wrong with the new password, shown under it
    private var newPasswordHint: String? {
        if sameAsCurrent { return "Your new password must be different from your current password." }
        if mismatch { return "The passwords don't match." }
        return nil
    }

    // MARK: - Screen

    var body: some View {
        NavigationStack {
            Group {
                if didChange {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.green)
                        Text("Password changed")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
            }
        }
        .tint(PLColor.accent)
    }

    private var form: some View {
        Form {
            Section {
                if proof == .currentPassword {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                } else {
                    HStack {
                        TextField("6-digit code", text: codeBinding)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        if isSendingCode {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(codeSent ? "Resend" : "Send Code") { sendCode() }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            } header: {
                Text(proof == .currentPassword ? "Current password" : "Code from a text")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if proof == .textCode, codeSent, let phone {
                        Text("Sent to the phone ending in \(String(phone.suffix(4))).")
                    }
                    Button(proof == .currentPassword ? "Forgot it? Text me a code instead" : "Use my current password instead") {
                        switchProof()
                    }
                    .font(.footnote.weight(.semibold))
                }
            }

            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
                PasswordChecklist(password: newPassword)
                    .padding(.vertical, 4)
            } header: {
                Text("New password")
            } footer: {
                if let newPasswordHint {
                    Text(newPasswordHint).foregroundColor(.red)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button { save() } label: {
                Group {
                    if isSaving { ProgressView().tint(.white) } else { Text("Change Password") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            .disabled(!canSave)
            .padding(PLSpacing.lg)
            .background(.bar)
        }
    }

    private var codeBinding: Binding<String> {
        Binding(get: { code }, set: { code = String($0.filter(\.isNumber).prefix(6)) })
    }

    // MARK: - Actions

    private func switchProof() {
        errorMessage = nil
        if proof == .currentPassword {
            proof = .textCode
            if !codeSent { sendCode() }
        } else {
            proof = .currentPassword
        }
    }

    private func sendCode() {
        guard !isSendingCode else { return }
        isSendingCode = true
        errorMessage = nil
        Task {
            defer { isSendingCode = false }
            do {
                if phone == nil {
                    let digits = (try await ProfileAPI.fetchPhone(username: username) ?? "").filter(\.isNumber)
                    guard digits.count == 10 else {
                        errorMessage = "Couldn't find the phone number on your account."
                        return
                    }
                    phone = digits
                }
                _ = try await AuthAPI.sendCode(phone: phone ?? "")
                codeSent = true
            } catch {
                errorMessage = "Couldn't send a code. \(AuthViewModel.message(for: error))"
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                if proof == .currentPassword {
                    _ = try await AuthAPI.changePassword(username: username, oldPassword: currentPassword, newPassword: newPassword)
                } else {
                    _ = try await AuthAPI.changePasswordWithCode(username: username, newPassword: newPassword, code: code)
                }
                didChange = true
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                isPresented = false
            } catch {
                errorMessage = Self.message(for: error, proof: proof)
                if proof == .textCode {
                    // a checked code can't be used again
                    code = ""
                    codeSent = false
                }
            }
        }
    }

    /// the server's reason, in words for this screen
    static func message(for error: Error, proof: Proof) -> String {
        let text = AuthViewModel.message(for: error)
        switch text {
        case "Incorrect old password": return "Your current password isn't right."
        case "Invalid OTP Code": return "That code isn't right or has expired. Send a new one."
        default:
            return proof == .textCode && text.contains("different from your current password")
                ? text + " Send a new code to try again."
                : text
        }
    }
}

#Preview("Current password") {
    ChangePasswordModalView(isPresented: .constant(true))
}

#Preview("Text code") {
    ChangePasswordModalView(isPresented: .constant(true), proof: .textCode)
}
