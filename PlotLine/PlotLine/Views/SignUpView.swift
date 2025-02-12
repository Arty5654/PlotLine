import SwiftUI

struct SignUpView: View {
    
    //Env Variables
    @EnvironmentObject var session: AuthViewModel
    
    //State variables
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confPassword: String = ""
    @State private var phoneNum: String = ""
    
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
                .font(.custom("AvenirNext-Bold", size: 36))                .foregroundColor(Color(.blue))
                .padding(.bottom, 25)
            
            // Text fields
            TextField("Phone Number", text: $phoneNum)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            SecureField("Confirm Password", text: $confPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
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
                    phone: phoneNum,
                    username: username,
                    password: password,
                    confPassword: confPassword
                )
            }) {
                Text("Sign Up")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.green)) // Green theme color
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // TODO make login page
            NavigationLink(
                destination: SignInView(),
                label: {
                    Text("Have an Account? Log in instead!")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
            )
            .padding(.top, 10)
        }
        .padding()
    }
    
    // TODO write func to get error message from auth if not successful

}



struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.light)
    }
}

