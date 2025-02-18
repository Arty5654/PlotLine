import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

struct SignInView: View {
    
    //Env Variables
    @EnvironmentObject var session: AuthViewModel
    
    //State variables
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var phoneNum: String = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field {
            case username, password, none
    }
    
    // UI variables
    
    var body: some View {
        VStack(spacing: 20) {
            // Logo Image
            Image("PlotLineLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .padding(.bottom, 0)
            
            // Title
            Text("PlotLine")
                .font(.custom("AvenirNext-Bold", size: 36))
                .foregroundColor(Color(.blue))
                .padding(.bottom, 25)
                
            
            TextField("Username", text: $username)
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focusedField == .username ? Color.blue : Color.gray, lineWidth: 2)
                )
                .focused($focusedField, equals: .username)
                .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 4)
                .padding(.horizontal)

            
            SecureField("Password", text: $password)
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focusedField == .password ? Color.blue : Color.gray, lineWidth: 2)
                )
                .focused($focusedField, equals: .password)
                .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 4)
                .padding(.horizontal)
            
            //Error in signing up
            if let error = session.loginErrorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                    .padding(.horizontal)
                    .transition(.opacity)
            }
            
            // Sign In Button
            Button(action: {
                session.signIn(username: username, password: password)
            }) {
                Text("Sign In")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .padding()
                    .frame(width: 220)
                    .background(Color(.green)) // Green theme color
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            GoogleSignInButton(action: {
                session.googleSignIn()
            })
            .frame(width: 140)
            .padding(.horizontal)
            .cornerRadius(10)
            .shadow(color: Color.gray.opacity(0.9), radius: 5, x: 2, y: 4)
            
            Button(action: {
                // display OTP screen for uname/password reset
            }) {
                Text("Forgot username or password?")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            }
            .padding(.top, 10)
            
            Spacer()
            
            Button(action: {
                session.isSignin = false
            }) {
                Text("No Account? Sign up now!")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            }
            .padding(.top, 10)
        }
        .padding()
    }
    
    // TODO write func to get error message from auth if not successful

}



struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.light)
    }
}
