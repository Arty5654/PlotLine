import SwiftUI

struct SignInView: View {
    
    //Env Variables
    @EnvironmentObject var session: AuthViewModel
    
    //State variables
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var phoneNum: String = ""
    @State private var errorMessage: String? = nil
    
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
            
            //Error in signing up
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                    .padding(.horizontal)
                    .transition(.opacity)
            }
            
            // Sign Up Button
            Button(action: {
                //todo call auth function
                
                session.signIn()
            }) {
                Text("Sign Up")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.green)) // Green theme color
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // TODO make login page
            Button(action: {
                // Navigate to log in page
            }) {
                Text("Log in instead")
                    .font(.system(size: 14))
                    .foregroundColor(Color(.green))
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
