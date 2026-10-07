import SwiftUI
import PhotosUI

struct ProfileView: View {
    @State private var username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"

    // profile fields
    @State private var displayName: String = ""
    
    @State private var birthday: Date = Date()
    
    @State private var homeCity: String = ""

    // image fields and overlay
    @State private var profileImageURL: URL?
    @State private var selectedImage: UIImage?
    
    @State private var showingImagePicker = false
    @State private var showingChangePasswordSheet = false

    // for save changes animations
    @State private var isUploading = false
    @State private var showSuccessModal = false
    @State private var animateSuccess = false
    
    @State private var showingTrophyHall = false
    @State private var showingDeleteAccount = false
    @State private var legalPage: LegalPage?

    @EnvironmentObject var session: AuthViewModel
    @Environment(\.dismiss) var dismiss // to close the sheet on signout

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PLSpacing.lg) {
                    header

                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Profile")
                        VStack(spacing: 0) {
                            PLFieldRow(label: "Name", placeholder: "Your name", text: $displayName)
                            Divider()
                            PLFieldRow(label: "Home city", placeholder: "City", text: $homeCity)
                            Divider()
                            DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                                .foregroundColor(PLColor.textPrimary)
                                .padding(.vertical, 2)
                        }
                        .plCard()

                        Button(action: saveProfileChanges) {
                            ZStack {
                                Text("Save Changes").opacity(isUploading ? 0 : 1)
                                if isUploading { ProgressView().tint(.white) }
                            }
                        }
                        .buttonStyle(PrimaryButton(color: PLColor.success))
                        .disabled(isUploading)
                        .padding(.top, 4)
                    }

                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Account")
                        VStack(spacing: 6) {
                            Button { showingTrophyHall = true } label: {
                                PLRow(icon: "trophy.fill", tint: .yellow, title: "Trophies")
                            }
                            Divider().padding(.leading, 42)
                            NavigationLink(destination: PaymentView()) {
                                PLRow(icon: "creditcard.fill", tint: PLColor.accent, title: "Membership & Billing")
                            }
                            Divider().padding(.leading, 42)
                            Button { showingChangePasswordSheet = true } label: {
                                PLRow(icon: "lock.fill", tint: .gray, title: "Change Password")
                            }
                        }
                        .buttonStyle(.plain)
                        .plCard()
                    }

                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Legal")
                        VStack(spacing: 6) {
                            Button { legalPage = .terms } label: {
                                PLRow(icon: "doc.text.fill", tint: .indigo, title: "Terms of Service")
                            }
                            Divider().padding(.leading, 42)
                            Button { legalPage = .privacy } label: {
                                PLRow(icon: "hand.raised.fill", tint: .teal, title: "Privacy Policy")
                            }
                        }
                        .buttonStyle(.plain)
                        .plCard()
                    }

                    VStack(spacing: PLSpacing.md) {
                        Button {
                            session.signOut()
                            dismiss()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(OutlineButton(tint: PLColor.danger))

                        Button("Delete Account") {
                            showingDeleteAccount = true
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(PLColor.danger)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.vertical, PLSpacing.md)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            fetchProfileData()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .fullScreenCover(isPresented: .constant(!session.isLoggedIn)) {
            AuthView()
        }
        .sheet(isPresented: $showingChangePasswordSheet) {
            ChangePasswordModalView(isPresented: $showingChangePasswordSheet)
        }
        .sheet(isPresented: $showingTrophyHall) {
            TrophyHallView(username: username)
        }
        .legalLinkSheet($legalPage)
        .sheet(isPresented: $showingDeleteAccount) {
            DeleteAccountView()
                .environmentObject(session)
        }
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            if !loggedIn { dismiss() }
        }
        .overlay(
            Group {
                if showSuccessModal {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(PLColor.success)
                        Text("Saved!")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.15), radius: 12)
                    .scaleEffect(animateSuccess ? 1.0 : 0.8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: animateSuccess)
                    .onAppear { animateSuccess = true }
                }
            }
        )
    }

    // photo (tap to change), name and @username
    private var header: some View {
        VStack(spacing: PLSpacing.sm) {
            Button { showingImagePicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let selectedImage {
                            Image(uiImage: selectedImage).resizable().scaledToFill()
                        } else if let profileImageURL {
                            AsyncImage(url: profileImageURL) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    avatarPlaceholder
                                }
                            }
                        } else {
                            avatarPlaceholder
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(PLColor.cardBorder))

                    Image(systemName: "camera.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(PLColor.accent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }
            .accessibilityLabel("Change profile photo")

            VStack(spacing: 2) {
                Text(displayName.isEmpty ? username : displayName)
                    .font(.title2.weight(.bold))
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
            }
        }
        .padding(.top, PLSpacing.sm)
    }

    private var avatarPlaceholder: some View {
        ZStack {
            PLColor.surface
            Image(systemName: "person.fill")
                .font(.system(size: 40))
                .foregroundColor(Color(.tertiaryLabel))
        }
    }

    private func saveProfileChanges() {
        isUploading = true
        Task {
            do {
                try await ProfileAPI.saveProfile(username: self.username,
                                                 name: self.displayName,
                                                 birthday: formatDate(self.birthday),
                                                 city: self.homeCity)

                if let selectedImage {
                    let result = try await ProfileAPI.uploadProfilePicture(image: selectedImage, username: self.username)
                    print("Profile picture uploaded: \(result)")

                    let newProfilePicURL = try await ProfileAPI.getProfilePic(username: self.username)
                    DispatchQueue.main.async {
                        if let urlString = newProfilePicURL, let url = URL(string: urlString) {
                            self.profileImageURL = url
                        }
                    }
                }

                DispatchQueue.main.async {
                    showSuccessModal = true
                    isUploading = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showSuccessModal = false
                        animateSuccess = false
                    }
                }
                print("Changes saved")
            } catch {
                isUploading = false
                AppBanner.report("save your profile", error, retry: { saveProfileChanges() })
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

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
                AppBanner.report("load your profile", error, retry: { fetchProfileData() })
            }
        }
    }

    private func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
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
        NavigationStack {
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
                                    self.errorMessage = AuthViewModel.message(for: error)
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
                                    _ = try await AuthAPI.sendCode(
                                        phone: self.phoneNumber
                                    )
                                } catch {
                                    AppBanner.report("send the passcode", error)
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
                                    self.errorMessage = AuthViewModel.message(for: error)
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
