import SwiftUI

struct SignUpView: View {
    
    //Env Variables
    @EnvironmentObject var session: AuthViewModel
    
    
    //State variables
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confPassword: String = ""
    @State private var rawPhone: String = ""
    @State private var formattedPhone: String = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field {
            case username, password, confPassword, phone, none
    }
    
    // UI variables
    
    var body: some View {
        VStack(spacing: 20) {
            // Logo Image
            Image("PlotLineLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150) // Adjust size as needed
                .padding(.bottom, 0)
            
            // Title
            Text("PlotLine")
                .font(.custom("AvenirNext-Bold", size: 36))
                .foregroundColor(Color(.blue))
                .padding(.bottom, 25)
            
            // Text fields
            TextField("Phone Number", text: $rawPhone)
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focusedField == .phone ? Color.blue : Color.gray, lineWidth: 2)
                )
                .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 4)
                .focused($focusedField, equals: .phone)
                .padding(.horizontal)
                .keyboardType(.phonePad)
            
            TextField("Username", text: $username)
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focusedField == .username ? Color.blue : Color.gray, lineWidth: 2)
                )
                .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 4)
                .focused($focusedField, equals: .username)
                .padding(.horizontal)
                
            SecureField("Password", text: $password)
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focusedField == .password ? Color.blue : Color.gray, lineWidth: 2)
                )
                .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 4)
                .focused($focusedField, equals: .password)
                .padding(.horizontal)
            
            SecureField("Confirm Password", text: $confPassword)
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focusedField == .confPassword ? Color.blue : Color.gray, lineWidth: 2)
                )
                .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 4)
                .focused($focusedField, equals: .confPassword)
                .padding(.horizontal)
            
            //Error in signing up
            if let error = session.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                    .padding(.horizontal)
                    .transition(.opacity)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Sign Up Button
            Button(action: {
                //todo call auth function
                
                session.signUp(
                    phone: rawPhone,
                    username: username,
                    password: password,
                    confPassword: confPassword
                )
            }) {
                Text("Sign Up")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .padding()
                    .frame(width: 220)
                    .background(Color(.green)) // Green theme color
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // TODO make login page
            Button(action: {
                session.isSignin = true
            }) {
                Text("Have an Account? Log in instead!")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            }
            .padding(.top, 10)
        }
        .padding()
    }
 
    
    
}




struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.light)
    }
}

