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
    @EnvironmentObject var calendarVM: CalendarViewModel
    @State private var friendStatus: FriendStatus? = nil
    @State private var currentUsername: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"

    // Calendar invite UI state
    @State private var showInviteSheet = false
    @State private var inviteLevel: String = "view"
    @State private var inviteRequireApproval: Bool = false
    @State private var showRevokeAlert = false

    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    // Derived calendar access status for this friend
    private var calendarInviteStatus: CalendarInviteStatus {
        if calendarVM.accessData.pendingOutgoing.contains(where: { $0.toUsername.lowercased() == username.lowercased() }) {
            return .pendingOutgoing
        }
        if calendarVM.accessData.pendingIncoming.contains(where: { $0.fromUsername.lowercased() == username.lowercased() }) {
            return .pendingIncoming
        }
        if calendarVM.accessData.granted.contains(where: { $0.friendUsername.lowercased() == username.lowercased() }) {
            return .granted
        }
        return .none
    }

    enum CalendarInviteStatus {
        case none, pendingOutgoing, pendingIncoming, granted
    }

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
                                        .overlay(Circle().stroke(adaptiveTextColor, lineWidth: 2))
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
                                .foregroundColor(adaptiveTextColor)

                            Text(city == "Unknown"
                                 ? "No Hometown given"
                                 : "Based out of \(city)")
                                .font(.custom("AvenirNext-Bold", size: 16))
                                .foregroundColor(adaptiveTextColor)
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
                                        friendStatus = .pendingRequest
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
                                VStack(spacing: 8) {
                                    Text("You are friends")
                                        .foregroundColor(.green)
                                        .fontWeight(.bold)

                                    // Calendar invite section
                                    switch calendarInviteStatus {
                                    case .none:
                                        Button("Invite to My Calendar") {
                                            showInviteSheet = true
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.purple)

                                    case .pendingOutgoing:
                                        Text("Calendar invite sent")
                                            .foregroundColor(.secondary)
                                            .italic()
                                            .font(.subheadline)

                                    case .pendingIncoming:
                                        if let invite = calendarVM.accessData.pendingIncoming.first(where: { $0.fromUsername.lowercased() == username.lowercased() }) {
                                            VStack(spacing: 4) {
                                                Text("\(username) invited you to their calendar")
                                                    .font(.subheadline)
                                                HStack(spacing: 12) {
                                                    Button("Accept") {
                                                        calendarVM.respondToCalendarInvite(inviteId: invite.id, accept: true)
                                                    }
                                                    .buttonStyle(.borderedProminent)
                                                    .tint(.green)
                                                    Button("Decline") {
                                                        calendarVM.respondToCalendarInvite(inviteId: invite.id, accept: false)
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .tint(.red)
                                                }
                                            }
                                        }

                                    case .granted:
                                        VStack(spacing: 8) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "calendar.badge.checkmark")
                                                    .foregroundColor(.purple)
                                                Text("Calendar access active")
                                                    .font(.subheadline)
                                                    .foregroundColor(.purple)
                                            }
                                            Button("Revoke Calendar Access") {
                                                showRevokeAlert = true
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(.red)
                                            .font(.subheadline)
                                        }
                                        .alert("Revoke Calendar Access", isPresented: $showRevokeAlert) {
                                            Button("Remove Their Events", role: .destructive) {
                                                calendarVM.revokeCalendarAccess(from: username, keepEvents: false)
                                            }
                                            Button("Keep Their Events", role: .none) {
                                                calendarVM.revokeCalendarAccess(from: username, keepEvents: true)
                                            }
                                            Button("Cancel", role: .cancel) {}
                                        } message: {
                                            Text("This will remove \(username)'s access to your calendar. Do you want to keep the events they added, or remove them?")
                                        }
                                    }

                                    // Show when friend has granted us access to their calendar
                                    if calendarVM.accessData.receivedAccess.contains(where: { $0.friendUsername.lowercased() == username.lowercased() }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "calendar.badge.checkmark")
                                                .foregroundColor(.green)
                                            Text("You can view their calendar")
                                                .font(.subheadline)
                                                .foregroundColor(.green)
                                        }
                                    }

                                    Button(role: .destructive) {
                                        Task {
                                            await viewModel.removeFriend(user: currentUsername, friend: username)
                                            await fetchFriendStatus()
                                        }
                                    } label: {
                                        Text("Remove Friend")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .sheet(isPresented: $showInviteSheet) {
                                    NavigationView {
                                        Form {
                                            Section(header: Text("Access Level")) {
                                                Picker("Level", selection: $inviteLevel) {
                                                    Text("View only").tag("view")
                                                    Text("View & add events").tag("add")
                                                }
                                                .pickerStyle(.segmented)
                                            }
                                            if inviteLevel == "add" {
                                                Section(header: Text("Approval")) {
                                                    Toggle("Require my approval for added events", isOn: $inviteRequireApproval)
                                                        .tint(.blue)
                                                }
                                            }
                                        }
                                        .navigationBarTitle("Invite to Calendar", displayMode: .inline)
                                        .navigationBarItems(
                                            leading: Button("Cancel") { showInviteSheet = false },
                                            trailing: Button("Send") {
                                                calendarVM.sendCalendarInvite(to: username, level: inviteLevel, requireApproval: inviteRequireApproval)
                                                showInviteSheet = false
                                            }.bold()
                                        )
                                    }
                                }
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
                            calendarVM.fetchAccessData()
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
        do {
            let friends = try await FriendsAPI.fetchFriendList(username: currentUsername).friends
            let incoming = try await FriendsAPI.fetchFriendRequests(username: currentUsername).pendingRequests
            let outgoing = try await FriendsAPI.fetchFriendRequests(username: username).pendingRequests

            if friends.contains(username) {
                friendStatus = .friends
            } else if incoming.contains(username) {
                friendStatus = .incomingRequest
            } else if outgoing.contains(currentUsername) {
                friendStatus = .pendingRequest
            } else {
                friendStatus = .notFriends
            }
        } catch {
            print("Error fetching friend status: \(error)")
        }
    }

}

struct FriendProfileView_Previews: PreviewProvider {
    static var previews: some View {
        FriendProfileView(username: "JDoeeeee")
    }
}
