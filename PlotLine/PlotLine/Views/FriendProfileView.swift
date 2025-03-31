import SwiftUI

struct FriendProfileView: View {
    
    let username: String
    
    @State private var displayName: String = ""
    @State private var city: String = ""
    @State private var profileImageURL: URL?
    
    init(friendUsername: String) {
        self.username = friendUsername
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {

                
                if let profileImageURL = profileImageURL {
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
                    Circle()
                        .frame(width: 120, height: 120)
                        .foregroundColor(.gray.opacity(0.3))
                }
                
                VStack(spacing: 16) {
                    Text("\(displayName)")
                        .font(.custom("AvenirNext-Bold", size: 20))
                        .foregroundColor(.blue)
                    
                        .font(.custom("AvenirNext-Bold", size: 20))
                        .foregroundColor(.blue)
                    
                    Text(self.city == "Unknown" ? "No Hometown given" : "Based out of \(city)")
                        .font(.custom("AvenirNext-Bold", size: 20))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 300)
                    .overlay(
                    Text("Trophies coming soon!")
                    .font(.custom("AvenirNext-Bold", size: 18))
                    .foregroundColor(.black)
                )
                .padding(.horizontal)
                            
                Spacer()
            }
            .padding()
            .navigationBarTitle("\(username)'s Profile", displayMode: .inline)
            .onAppear {
                fetchFriendProfile()
            }
        }
    }
    
    
    private func fetchFriendProfile() {
        Task {
            do {
                let profile = try await ProfileAPI.fetchProfile(username: username)
                let profilePicStr = try await ProfileAPI.getProfilePic(username: username)
                // Update UI on the main thread
                await MainActor.run {
                    self.displayName = profile.name ?? username
                    if (profile.city == "") {
                        self.city = "Unknown"
                    } else {
                        self.city = profile.city ?? "Unknown"
                    }
                    if let profilePicStr = profilePicStr,
                        let url = URL(string: profilePicStr) {
                        self.profileImageURL = url
                    }
                }
            } catch {
                self.displayName = username
                self.city = "Unknown"
                print("Error fetching friend profile: \(error)")
            }
        }
    }
}

struct FriendProfileView_Previews: PreviewProvider {
    static var previews: some View {
        FriendProfileView(
            friendUsername: "JDoeeeee"
        )
    }
}
