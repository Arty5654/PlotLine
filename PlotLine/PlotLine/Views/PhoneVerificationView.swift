//
//  PhoneVerificationView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/18/25.
//

import SwiftUI

struct PhoneVerificationView: View {
    
    @EnvironmentObject var session: AuthViewModel
    @State private var phoneNumber: String = ""
    @State private var isEditingNumber = false
    @State private var codeInput = ""
    @State private var isOptedIn = false
    
    var body: some View {
        
        VStack(spacing: 20) {
            // Logo Image
            Image("PlotLineLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .padding(.bottom, 0)
            
            // Title
            Text("Verify Your Phone!")
                .font(.custom("AvenirNext-Bold", size: 24))
                .foregroundColor(Color(.blue))
                .padding(.bottom, 15)
            
            if (!session.isCodeSent) {
                
                // Phone check and send code step (before sending text)
                Text("This step ensures you have a quick way to access your account if you are locked out or forget your password.")
                    .font(.custom("AvenirNext-Bold", size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 25)
                

                if isEditingNumber {
                    TextField("Enter your phone number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray, lineWidth: 1)
                        )
                        .padding(.horizontal, 30)
                    
                    Button("Save") {
                        isEditingNumber = false
                    }
                    .padding(.top, 4)
                    .font(.custom("AvenirNext-Bold", size: 16))
                    
                } else {
                    
                    // if google add number
                    if phoneNumber.isEmpty {
                        Text("Please Add Your Phone Number")
                            .font(.custom("AvenirNext-Bold", size: 18))
                            .foregroundColor(.black)
                        
                        // "Edit" button
                        Button("Add") {
                            isEditingNumber = true
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .font(.custom("AvenirNext-Bold", size: 16))
                        
                    } else {
                        //prefilled
                        Text("Your Phone Number:")
                            .font(.headline)
                        Text(phoneNumber)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Button("Edit") {
                            isEditingNumber = true
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .font(.custom("AvenirNext-Bold", size: 16))
                    }
                }
                
                // Opt-in Checkbox
                HStack {
                    Button(action: {
                        isOptedIn.toggle()
                    }) {
                        Image(systemName: isOptedIn ? "checkmark.square.fill" : "square")
                            .foregroundColor(isOptedIn ? .blue : .gray)
                    }
                    Text("Opt-in to receive text messages (Message & data rates may apply)")
                        .font(.custom("AvenirNext-Regular", size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, 5)
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)
                
                Spacer()
                
                Button("Send SMS Code") {
                    session.sendSmsCode(phone: phoneNumber)
                }
                .font(.custom("AvenirNext-Bold", size: 20))
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(8)
                .padding(.horizontal, 40)
                .padding(.bottom, 10)
                .disabled(!isPhoneNumberValid(phoneNumber))
                
                
            } else {
                
                TextField("Enter the code you received", text: $codeInput)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                    
                Spacer()
                    
                Button("Verify") {
                    // TODO: Add verification logic
                }
                .font(.custom("AvenirNext-Bold", size: 20))
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(8)
                .padding(.horizontal, 60)
                
                Button("Resend Code") {
                    // TODO: Call code send again
                }
                .font(.footnote)
                .foregroundColor(.blue)
                .padding(.bottom, 30)
            }
        }
        .padding()
        .onAppear {
            self.phoneNumber = session.phoneNumber
        }
    }
    
    private func isPhoneNumberValid(_ number: String) -> Bool {
        let digits = number.filter(\.isNumber).count
        return digits >= 10
    }
}

#Preview {
    PhoneVerificationView()
        .environmentObject(AuthViewModel())
}

