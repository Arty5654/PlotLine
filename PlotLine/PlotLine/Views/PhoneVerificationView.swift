//
//  PhoneVerificationView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/18/25.
//

import SwiftUI

struct PhoneVerificationView: View {

    @EnvironmentObject var session: AuthViewModel
    @State private var username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    @State private var rawPhone: String = ""      // 10 digits; the backend adds +1
    @State private var codeInput = ""
    @State private var isOptedIn = false

    @FocusState private var focusedField: Field?
    enum Field { case phone, code }

    private var phoneValid: Bool { rawPhone.count == 10 }
    private var formattedPhone: String { SignUpView.formatUSPhone(rawPhone) }

    var body: some View {
        ScrollView {
            VStack(spacing: AuthStyle.spacing) {
                AuthHero(title: session.isCodeSent ? "Enter your code" : "Verify your phone",
                         subtitle: session.isCodeSent
                            ? "We texted a 6-digit code to \(rawPhone.isEmpty ? "your phone" : formattedPhone)."
                            : "This gives you a quick way back into your account if you ever get locked out or forget your password.")
                    .padding(.top, 24)

                if session.isCodeSent {
                    codeStep
                } else {
                    phoneStep
                }

                Button("Use a different account") {
                    session.signOut()
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, AuthStyle.spacing)
            .padding(.bottom, AuthStyle.spacing)
            .animation(.easeInOut(duration: 0.2), value: session.isCodeSent)
            .animation(.easeOut(duration: 0.2), value: session.verificationErrorMessage)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .onAppear {
            rawPhone = String(session.phoneNumber.filter(\.isNumber).suffix(10))
        }
    }

    // MARK: Step 1: phone number + consent

    private var phoneStep: some View {
        VStack(spacing: 14) {
            AuthField(icon: "phone", placeholder: "Phone number", text: phoneBinding,
                      focus: $focusedField, field: .phone,
                      contentType: .telephoneNumber, keyboard: .numberPad,
                      isInvalid: !rawPhone.isEmpty && !phoneValid)

            Button {
                isOptedIn.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isOptedIn ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(isOptedIn ? AuthStyle.accent : .secondary)
                    Text("I agree to receive text messages from PlotLine. Message and data rates may apply.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOptedIn ? .isSelected : [])

            if let error = session.verificationErrorMessage, !error.isEmpty {
                AuthMessage(text: error)
            }

            AuthPrimaryButton(title: "Send Code",
                              isLoading: session.phoneStepInFlight,
                              isEnabled: phoneValid && isOptedIn) {
                focusedField = nil
                session.sendSmsCode(phone: rawPhone)
            }
        }
        .authCard()
        .transition(.opacity)
    }

    // MARK: Step 2: code

    private var codeStep: some View {
        VStack(spacing: 14) {
            TextField("000000", text: codeBinding)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(8)
                .focused($focusedField, equals: .code)
                .frame(height: 64)
                .background(AuthStyle.field)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(focusedField == .code ? AuthStyle.accent : AuthStyle.cardBorder, lineWidth: 1.5))
                .accessibilityLabel("Verification code")

            if let error = session.verificationErrorMessage, !error.isEmpty {
                AuthMessage(text: error)
            }

            AuthPrimaryButton(title: "Verify",
                              isLoading: session.phoneStepInFlight,
                              isEnabled: codeInput.count >= 4) {
                focusedField = nil
                session.verifyCode(phone: rawPhone, code: codeInput, username: username)
            }

            HStack {
                Button("Change number") {
                    codeInput = ""
                    session.verificationErrorMessage = nil
                    session.isCodeSent = false
                }
                Spacer()
                Button("Resend code") {
                    codeInput = ""
                    session.sendSmsCode(phone: rawPhone)
                }
                .disabled(session.phoneStepInFlight)
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(AuthStyle.accent)
        }
        .authCard()
        .transition(.opacity)
        .onAppear { focusedField = .code }
    }

    private var phoneBinding: Binding<String> {
        Binding(get: { formattedPhone },
                set: { rawPhone = String($0.filter(\.isNumber).prefix(10)) })
    }

    private var codeBinding: Binding<String> {
        Binding(get: { codeInput },
                set: { codeInput = String($0.filter(\.isNumber).prefix(6)) })
    }
}

#Preview {
    PhoneVerificationView()
        .environmentObject(AuthViewModel())
}
