import SwiftUI
import PhotosUI

struct ProfileView: View {
    
    @State private var username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    
    // profile fields
    @State private var displayName: String = ""
    @State private var isEditingDisplayName = false
    
    @State private var birthday: Date = Date()
    @State private var isEditingBirthday = false
    
    @State private var homeCity: String = ""
    @State private var isEditingHomeCity = false
    
    // image fields and overlay
    @State private var profileImageURL: URL?
    @State private var selectedImage: UIImage?
    
    @State private var showingImagePicker = false
    @State private var showingChangePasswordSheet = false
    
    // for save changes animations
    @State private var isUploading = false
    @State private var showSuccessModal = false
    
    @State private var showingTrophyHall = false

    
    @EnvironmentObject var session: AuthViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        
        NavigationStack {
            
            ScrollView {
                
                VStack(spacing: 20) {
                    
                    // profile picture (click to change)
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        ZStack {
                            if let selectedImage {
                                // user selects new image from camera roll
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                            } else if let profileImageURL {
                                
                                // pre-existing image loaded from DB
                                AsyncImage(url: profileImageURL) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                                    } else {
                                        Circle()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.gray.opacity(0.3))
                                    }
                                }
                            } else {
                                // default / no image
                                Circle()
                                    .frame(width: 120, height: 120)
                                    .foregroundColor(.gray.opacity(0.3))
                            }
                            
                            
                            Image(systemName: "camera.fill")
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .offset(x: 55, y: 45)
                        }
                    }
                    
                    
                    // name field
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Display Name")
                            .font(.custom("AvenirNext-Bold", size: 15))
                            .foregroundColor(.gray)
                        
                        HStack {
                            if isEditingDisplayName {
                                TextField("Enter new name", text: $displayName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.vertical, 8)
                            } else {
                                Text(displayName.isEmpty ? "Tap to enter" : displayName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 8)
                            }
                            Button(action: {
                                isEditingDisplayName.toggle()
                            }) {
                                Image(systemName: isEditingDisplayName ? "checkmark" : "pencil")
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Circle().fill(Color(.systemGray4)))
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 30)
                    
                    
                    // city field
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Home City")
                            .font(.custom("AvenirNext-Bold", size: 15))
                            .foregroundColor(.gray)
                        
                        HStack {
                            if isEditingHomeCity {
                                TextField("Enter new city", text: $homeCity)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.vertical, 8)
                            } else {
                                Text(homeCity.isEmpty ? "Tap to enter" : homeCity)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 8)
                            }
                            Button(action: {
                                isEditingHomeCity.toggle()
                            }) {
                                Image(systemName: isEditingHomeCity ? "checkmark" : "pencil")
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Circle().fill(Color(.systemGray4)))
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 30)
                    
                    
                    // birthday field
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Birthday")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        HStack {
                            if isEditingBirthday {
                                DatePicker("", selection: $birthday, displayedComponents: .date)
                                    .datePickerStyle(CompactDatePickerStyle())
                                    .labelsHidden()
                            } else {
                                Text(birthdayFormatted)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 8)
                            }
                            Button(action: { isEditingBirthday.toggle() }) {
                                Image(systemName: isEditingBirthday ? "checkmark" : "pencil")
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Circle().fill(Color(.systemGray4)))
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    
                    
                    Button("Save Changes") {
                        saveProfileChanges()
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Spacer()
                    
                    Button("Change Password") {
                        showingChangePasswordSheet = true
                    }
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Spacer()
                    
                    Button(action: {
                        session.signOut()
                    }) {
                        Label("Sign Out", systemImage: "arrow.backward.circle.fill")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.red))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    .padding([.horizontal, .bottom])
                }
                .padding()
                .frame(maxWidth: .infinity)
                
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(self.username)
                        .font(.custom("AvenirNext-Bold", size: 20))
                        .foregroundColor(Color.blue)
                }
            }
            .navigationBarItems(
                trailing: Button(action: {
                    showingTrophyHall = true
                }) {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
                }
            )
            
        }
        .onAppear {
            fetchProfileData()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .fullScreenCover(isPresented: .constant(!session.isLoggedIn)) {
            AuthView()  // Redirects to AuthView when logged out
        }
        .onChange(of: session.isLoggedIn, initial: false) { oldValue, newValue in
            if !newValue {
                presentationMode.wrappedValue.dismiss()
            }
        }
        .sheet(isPresented: $showingChangePasswordSheet) {
                    ChangePasswordModalView(isPresented: $showingChangePasswordSheet)
        }
        .sheet(isPresented: $showingTrophyHall) {
            TrophyHallView(username: username)
        }
        .overlay(
            // overlay for after changes are saved
            Group {
            if showSuccessModal {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.green)
                        .transition(.scale)
                    
                    Text("Saved!")
                        .font(.headline)
                        .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 10)
                    .frame(width: 150, height: 150)
                    .opacity(showSuccessModal ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.3), value: showSuccessModal)
                }
        })

        
    }

    // grab data from backend on appear
    private func fetchProfileData() {
        Task {
            do {
                let profile = try await ProfileAPI.fetchProfile(username: self.username)
                let profilePicURL = try await ProfileAPI.getProfilePic(username: self.username)
                DispatchQueue.main.async {
                    self.displayName = profile.name ?? ""
                    self.birthday = parseDate(profile.birthday ?? "")
                    self.homeCity = profile.city ?? ""
                    if let urlString = profilePicURL, let url = URL(string: urlString) {
                        self.profileImageURL = url
                    }
                }
            } catch {
                print("Error fetching profile: \(error)")
            }
        }
        
    }
    
    private func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
    }
    
    private func saveProfileChanges() {
        
        
        Task {
            do {
                try await ProfileAPI.saveProfile(username: self.username,
                                                 name: self.displayName,
                                                 birthday: formatDate(self.birthday),
                                                 city: self.homeCity)
                
                if let selectedImage {
                    let result = try await ProfileAPI.uploadProfilePicture(image: selectedImage, username: self.username)
                    print("Profile picture uploaded: \(result)")
                                
                    // Fetch updated profile pic URL
                    let newProfilePicURL = try await ProfileAPI.getProfilePic(username: self.username)
                    DispatchQueue.main.async {
                        if let urlString = newProfilePicURL, let url = URL(string: urlString) {
                            self.profileImageURL = url
                        }
                    }
                }
                
                // show saved modal
                DispatchQueue.main.async {
                    showSuccessModal = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showSuccessModal = false
                    }
                }
                
                print("Changes saved")
            } catch {
                print("error saving changes")
            }
        }
        
        
    }
    
    // date formatter
    private var birthdayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: birthday)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    
}

// using swiftUI version of PHPicker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}

struct ChangePasswordModalView: View {
    @Binding var isPresented: Bool
    
    @State private var useOTPFlow = false
    @State private var username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    
    @State private var oldPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    
    @State private var phoneNumber: String = ""
    @State private var otpCode: String = ""
    
    @State private var errorMessage: String?

    
    var body: some View {
        NavigationView {
            Form {
                if !useOTPFlow {
                    
                    Section(header: Text("Change Password with current PW")) {
                        SecureField("Current Password", text: $oldPassword)
                        SecureField("New Password", text: $newPassword)
                        SecureField("Confirm New Password", text: $confirmPassword)
                        
                        Button("Save") {
                            self.errorMessage = nil
                            
                            Task {
                                guard newPassword == confirmPassword else {
                                    self.errorMessage = "New passwords do not match."
                                    return
                                }

                                do {
                                    let success = try await AuthAPI.changePassword(username: username, oldPassword: oldPassword, newPassword: newPassword)
                                    if success {
                                        isPresented = false
                                    } else {
                                        self.errorMessage = "Failed to change password. Incorrect Old Password"
                                    }
                                } catch {
                                    self.errorMessage = "An error occurred. Please try again."
                                }
                            }
                        }
                        .disabled(oldPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                    }
                } else {
                    Section(header: Text("Change Password with OTP")) {
                        //send otp to acct phone num
                        Button("Send One-Time-Passcode") {
                            Task {
                                do {
                                    try await AuthAPI.sendCode(
                                        phone: self.phoneNumber
                                    )
                                } catch {
                                    print("error")
                                }
                            }
                        }
                        
                        TextField("Enter OTP", text: $otpCode)
                            .keyboardType(.numberPad)
                        
                        SecureField("New Password", text: $newPassword)
                        SecureField("Confirm New Password", text: $confirmPassword)
                        
                        Button("Verify & Save") {
                            self.errorMessage = nil
                            
                            guard newPassword == confirmPassword else {
                                self.errorMessage = "New passwords do not match."
                                return
                            }
                            
                            Task {
                                do {
                                    let success = try await AuthAPI.changePasswordWithCode(username: username, newPassword: newPassword, code: otpCode)
                                    if success {
                                        isPresented = false
                                    } else {
                                        self.errorMessage = "Invalid Code. Please Try again"
                                    }

                                } catch {
                                    print("An unexpected error occurred. Please try again.")
                                    self.errorMessage = "Invalid Code. Please Try again"
                                }
                                
                            }
                        }
                        .disabled(phoneNumber.isEmpty || otpCode.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
            }
            .navigationBarTitle("Change Password", displayMode: .inline)
            
            .navigationBarItems(
                trailing: Button(action: {
                    Task {
                            do {
                                // grab phone num once
                                if (self.phoneNumber == "") {
                                    let fetchedPhone = try await ProfileAPI.fetchPhone(username: self.username)
                                    self.phoneNumber = fetchedPhone ?? ""
                                }
                                
                                withAnimation {
                                    useOTPFlow.toggle()
                                    self.errorMessage = nil
                                }
                            } catch {
                                print("Error fetching phone: \(error)")
                            }
                        }
                }) {
                    Text(useOTPFlow ? "Use Old PW" : "Get A Text")
                }
            )
        }
    }
}


struct Profile_preview: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(AuthViewModel())
    }
}

