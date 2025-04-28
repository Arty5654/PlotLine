import SwiftUI

enum FriendStatus {
    case notFriends
    case pendingRequest
    case incomingRequest
    case friends
}

struct FriendProfileView: View {
    
    let username: String // friend uname

    @State private var displayName: String = ""
    @State private var city: String = ""
    @State private var profileImageURL: URL?
    @State private var friendTrophies: [Trophy] = []
    @State private var selectedTrophy: Trophy? = nil
    
    @EnvironmentObject var viewModel: FriendsViewModel
    @State private var friendStatus: FriendStatus? = nil
    @State private var currentUsername: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest" // searcher uname

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 30) {

                        // Profile Image
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

                        // Name and City
                        VStack(spacing: 8) {
                            Text(displayName)
                                .font(.custom("AvenirNext-Bold", size: 20))
                                .foregroundColor(.blue)

                            Text(city == "Unknown"
                                 ? "No Hometown given"
                                 : "Based out of \(city)")
                                .font(.custom("AvenirNext-Bold", size: 16))
                                .foregroundColor(.blue)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        
                        // Friend request button
                        
                        if username == currentUsername {
                            Text("This is you")
                                .foregroundColor(.gray)
                                .italic()
                            
                        } else if let status = friendStatus {
                            switch status {
                            case .notFriends:
                                Button("Add Friend") {
                                    Task {
                                        _ = await viewModel.sendFriendRequest(sender: currentUsername, receiver: username)
                                        await fetchFriendStatus()
                                        
                                        print("Sent request")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)

                            case .incomingRequest:
                                Button("Accept Request") {
                                    Task {
                                        _ = await viewModel.acceptFriendRequest(sender: username, receiver: currentUsername)
                                        
                                        await viewModel.loadFriends(for: currentUsername)
                                        await viewModel.loadPendingRequests(for: currentUsername)
                                        
                                        await fetchFriendStatus()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                            case .pendingRequest:
                                Text("Request Pending")
                                    .foregroundColor(.gray)
                                    .italic()

                            case .friends:
                                Text("You are friends")
                                    .foregroundColor(.green)
                                    .fontWeight(.bold)
                            }
                        }


                        // Trophy Section
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 300)
                            .overlay(
                                Group {
                                    if friendTrophies.isEmpty {
                                        VStack {
                                            Spacer()
                                            Text("No Trophies Yet!")
                                                .font(.custom("AvenirNext-Bold", size: 20))
                                                .foregroundColor(.black)
                                                .multilineTextAlignment(.center)
                                                .padding()
                                            Spacer()
                                        }
                                    } else {
                                        ScrollView {
                                            LazyVGrid(columns: columns, spacing: 20) {
                                                ForEach(friendTrophies) { trophy in
                                                    VStack {
                                                        Image(trophyImageName(for: trophy))
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(width: 60, height: 60)

                                                        Text(trophy.name)
                                                            .font(.caption)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(trophyColor(for: trophy.level))
                                                            .multilineTextAlignment(.center)
                                                    }
                                                    .onTapGesture {
                                                        withAnimation {
                                                            selectedTrophy = trophy
                                                        }
                                                    }
                                                }
                                            }
                                            .padding()
                                        }
                                    }
                                }
                            )
                            .padding(.horizontal)

                        Spacer(minLength: 40)
                    }
                    .padding()
                    .navigationBarTitle("\(username)'s Profile", displayMode: .inline)
                    .onAppear {
                        Task {
                            fetchFriendProfile()
                            fetchFriendTrophies()
                            await fetchFriendStatus()
                        }
                    }
                }
            }

            // Popup Trophy Detail
            if let selected = selectedTrophy {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            selectedTrophy = nil
                        }
                    }

                TrophyDetailPopup(trophy: selected) {
                    withAnimation {
                        selectedTrophy = nil
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .zIndex(1)
            }
        }
    }


    private func fetchFriendProfile() {
        Task {
            do {
                let profile = try await ProfileAPI.fetchProfile(username: username)
                let profilePicStr = try await ProfileAPI.getProfilePic(username: username)
                await MainActor.run {
                    self.displayName = (profile.name?.isEmpty == true) ? username : (profile.name ?? username)
                    self.city = (profile.city?.isEmpty == true) ? "Unknown" : (profile.city ?? "Unknown")
                    if let url = URL(string: profilePicStr ?? "") {
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

    private func fetchFriendTrophies() {
        Task {
            do {
                let data = try await ProfileAPI.fetchTrophies(username: username)
                await MainActor.run {
                    self.friendTrophies = data.filter { $0.level > 0 }
                }
            } catch {
                print("Error fetching friend trophies: \(error)")
            }
        }
    }

    private func trophyImageName(for trophy: Trophy) -> String {
        if trophy.id == "llm-investor" {
            return "llmTrophy"
        }
        if trophy.id == "first-profile-picture" { return "profilePicTrophy" }
        
        switch trophy.level {
        case 1: return "bronzeTrophy"
        case 2: return "silverTrophy"
        case 3: return "goldTrophy"
        case 4: return "diamondTrophy"
        default: return "bronzeTrophy"
        }
    }

    private func trophyColor(for level: Int) -> Color {
        switch level {
        case 1: return Color(red: 205/255, green: 127/255, blue: 50/255)
        case 2: return .gray
        case 3: return .yellow
        case 4: return .mint
        default: return .primary
        }
    }
    
    private func fetchFriendStatus() async {
        Task {
            do {
                let friends = try await FriendsAPI.fetchFriendList(username: currentUsername).friends
                let incoming = try await FriendsAPI.fetchFriendRequests(username: currentUsername).pendingRequests
                let outgoing = try await FriendsAPI.fetchFriendRequests(username: username).pendingRequests
                

                await MainActor.run {
                    if friends.contains(username) {
                        friendStatus = .friends
                    } else if incoming.contains(username) {
                        friendStatus = .incomingRequest
                    } else if outgoing.contains(currentUsername) {
                        friendStatus = .pendingRequest
                    } else {
                        friendStatus = .notFriends
                    }
                }
            } catch {
                print("Error fetching friend status: \(error)")
            }
        }
    }

}

struct FriendProfileView_Previews: PreviewProvider {
    static var previews: some View {
        FriendProfileView(username: "JDoeeeee")
    }
}
