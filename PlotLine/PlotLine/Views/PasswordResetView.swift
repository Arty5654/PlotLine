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
    @State private var phone: String = ""
    @State private var code: String = ""
    
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    
    @State private var isCodeSent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Image("PlotLineLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(.bottom, 0)
                
                Text("Reset Your Password")
                    .font(.custom("AvenirNext-Bold", size: 26))

                // send code to number/username
                if !isCodeSent {
                    TextField("Enter your username", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .padding()
                    
                    TextField("Enter your Phone number", text: $phone)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .padding()
                    
                    Button(action: {
                        requestPasswordReset()
                    }) {
                        Text("Send Reset Code")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                // change password with code
                if isCodeSent {
                    TextField("Enter OTP Code", text: $code)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .padding()
                    
                    SecureField("New Password", text: $newPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    SecureField("Confirm New Password", text: $confirmPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button(action: {
                        resetPassword()
                    }) {
                        Text("Verify Code & Reset Password")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    
                    Button(action: {
                        isCodeSent = false
                        code = ""
                        newPassword = ""
                        confirmPassword = ""
                        errorMessage = nil
                    }) {
                    Text("Change information and resend")
                        .foregroundColor(.blue)
                        .font(.caption)
                        .underline()
                    }
                }
                
                
                
                // Error Message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    // Function to request password reset
    private func requestPasswordReset() {
        Task {
            do {
                try await AuthAPI.sendCode(phone: phone)
                isCodeSent = true
                errorMessage = nil
            } catch {
                errorMessage = "Failed to send reset code. Try again."
            }
        }
    }
    
    // Function to verify code & reset password
    private func resetPassword() {
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        
        Task {
            do {
                let success = try await AuthAPI.changePasswordWithCode(username: username, newPassword: newPassword, code: code)
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                } else {
                    errorMessage = "Invalid code or failed to reset."
                }
            } catch {
                errorMessage = "Something went wrong. Try again."
            }
        }
    }
}

struct PasswordResetView_Previews: PreviewProvider {
    static var previews: some View {
        PasswordResetView()
    }
}
