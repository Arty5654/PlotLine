//
//  PhoneVerificationView.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/18/25.
//


import SwiftUI



struct PhoneVerificationView: View {
    
    @EnvironmentObject var session: AuthViewModel
    
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
                .padding(.bottom, 25)
            
            Spacer()
            
        }
    }
}

#Preview {
    PhoneVerificationView()
        .environmentObject(AuthViewModel())
}
