import SwiftUI
import PhotosUI

struct ProfileView: View {
    
    @State private var username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    
    @State private var displayName: String = ""
    @State private var isEditingDisplayName = false
    
    @State private var birthday: Date = Date()
    @State private var isEditingBirthday = false
    
    @State private var homeCity: String = ""
    @State private var isEditingHomeCity = false
    
    @State private var phoneNumber: String = ""
    @State private var isEditingPhone = false
    
    @State private var profileImageURL: URL?
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    
    @State private var isUploading = false
    
    var body: some View {
        
        NavigationView {
            
            ScrollView {
                
                VStack(spacing: 20) {
                    
                    // profile picture (click to change)
                    
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        ZStack {
                            if let selectedImage {
                                // show image if there is one
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                            } else if let profileImageURL {
                                
                                // pre-existing image
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
                    
                    // phone num field
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Phone Number")
                            .font(.custom("AvenirNext-Bold", size: 15))
                            .foregroundColor(.gray)
                        
                        HStack {
                            if isEditingPhone {
                                TextField("Enter new phone", text: $phoneNumber)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.vertical, 8)
                            } else {
                                Text(phoneNumber.isEmpty ? "Tap to enter" : phoneNumber)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 8)
                            }
                            Button(action: {
                                isEditingPhone.toggle()
                            }) {
                                Image(systemName: isEditingPhone ? "checkmark" : "pencil")
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
                        // todo api call to save profile changes to db
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Spacer()
                    
                    Button("Change Password") {
                        // make navigation stack to phoneverification view -> route that back here for a passwordReset modal
                    }
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(self.username)  // Customize this title
                        .font(.custom("AvenirNext-Bold", size: 20))  // Custom Font
                        .foregroundColor(Color.blue)  // Custom Color
                }
            }
            .navigationBarItems(
                leading: Button(action: {
                    // for friends function in later sprint
                }) {
                    Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)
                },
                trailing: Button(action: {
                    // for trophy function in later sprint
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

        
    }

    // grab data from backend on appear
    private func fetchProfileData() {
        Task {
            do {
                let profile = try await ProfileAPI.fetchProfile(username: self.username)
                DispatchQueue.main.async {
                    self.displayName = profile.name ?? ""
                    self.birthday = parseDate(profile.birthday ?? "")
                    self.homeCity = profile.city ?? ""
                    self.phoneNumber = profile.phone

                    if let imageUrlString = profile.profileUrl, let imageUrl = URL(string: imageUrlString) {
                        self.profileImageURL = imageUrl
                    } else {
                        self.profileImageURL = nil
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
        
        let profileImageString: String? = self.profileImageURL?.absoluteString
        Task {
            do {
                try await ProfileAPI.saveProfile(username: self.username,
                                                 name: self.displayName,
                                                 birthday: formatDate(self.birthday),
                                                 phone: self.phoneNumber,
                                                 city: self.homeCity,
                                                 profileUrl: profileImageString)
                
                print("Changes saved!")
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
        formatter.dateFormat = "yyyy-MM-dd" // Ensure this matches the backend format
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


struct Profile_preview: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}

