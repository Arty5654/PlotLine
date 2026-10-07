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
            ScrollView {
                VStack(spacing: PLSpacing.lg) {
                    header

                    if username.lowercased() == currentUsername.lowercased() {
                        Text("This is you")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                    } else if let status = friendStatus {
                        friendshipSection(status)
                    }

                    trophiesSection
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.vertical, PLSpacing.md)
                .navigationBarTitle(username, displayMode: .inline)
                .onAppear {
                    Task {
                        fetchFriendProfile()
                        fetchFriendTrophies()
                        await fetchFriendStatus()
                        calendarVM.fetchAccessData()
                    }
                }
            }
            .sheet(isPresented: $showInviteSheet) { inviteSheet }
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

    // photo, name and hometown
    private var header: some View {
        VStack(spacing: PLSpacing.sm) {
            Group {
                if let profileImageURL {
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

            VStack(spacing: 4) {
                Text(displayName.isEmpty ? username : displayName)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if city.isEmpty || city == "Unknown" {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                } else {
                    Label(city, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                }
                if friendStatus == .friends {
                    Label("Friends", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(PLColor.success)
                        .padding(.top, 2)
                }
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

    @ViewBuilder
    private func friendshipSection(_ status: FriendStatus) -> some View {
        switch status {
        case .notFriends:
            Button {
                Task {
                    _ = await viewModel.sendFriendRequest(sender: currentUsername, receiver: username)
                    friendStatus = .pendingRequest
                }
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
            }
            .buttonStyle(PrimaryButton())

        case .incomingRequest:
            Button {
                Task {
                    _ = await viewModel.acceptFriendRequest(sender: username, receiver: currentUsername)
                    await viewModel.loadFriends(for: currentUsername)
                    await viewModel.loadPendingRequests(for: currentUsername)
                    await fetchFriendStatus()
                }
            } label: {
                Label("Accept Friend Request", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButton(color: PLColor.success))

        case .pendingRequest:
            Label("Friend request sent", systemImage: "clock")
                .font(.subheadline)
                .foregroundColor(PLColor.textSecondary)
                .frame(maxWidth: .infinity)
                .plCard()

        case .friends:
            VStack(spacing: PLSpacing.sm) {
                PLSectionHeader(title: "Calendar sharing")
                VStack(alignment: .leading, spacing: 12) {
                    calendarStatus
                    // when the friend has shared their calendar with us
                    if calendarVM.accessData.receivedAccess.contains(where: { $0.friendUsername.lowercased() == username.lowercased() }) {
                        Divider()
                        Label("You can see their calendar", systemImage: "calendar.badge.checkmark")
                            .font(.subheadline)
                            .foregroundColor(PLColor.success)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .plCard()

                Button(role: .destructive) {
                    Task {
                        await viewModel.removeFriend(user: currentUsername, friend: username)
                        await fetchFriendStatus()
                    }
                } label: {
                    Text("Remove Friend")
                }
                .buttonStyle(OutlineButton(tint: PLColor.danger))
                .padding(.top, 4)
            }
        }
    }

    // sharing my calendar with this friend
    @ViewBuilder
    private var calendarStatus: some View {
        switch calendarInviteStatus {
        case .none:
            Button {
                showInviteSheet = true
            } label: {
                PLRow(icon: "calendar.badge.plus", tint: .purple, title: "Share my calendar")
            }
            .buttonStyle(.plain)

        case .pendingOutgoing:
            PLRow(icon: "clock", tint: .gray, title: "Calendar invite sent", showsChevron: false)

        case .pendingIncoming:
            if let invite = calendarVM.accessData.pendingIncoming.first(where: { $0.fromUsername.lowercased() == username.lowercased() }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(username) invited you to their calendar")
                        .font(.subheadline)
                    HStack(spacing: 12) {
                        Button("Accept") {
                            calendarVM.respondToCalendarInvite(inviteId: invite.id, accept: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PLColor.success)
                        Button("Decline") {
                            calendarVM.respondToCalendarInvite(inviteId: invite.id, accept: false)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
            }

        case .granted:
            VStack(alignment: .leading, spacing: 10) {
                PLRow(icon: "calendar.badge.checkmark", tint: .purple, title: "They can see your calendar", showsChevron: false)
                Button("Stop sharing my calendar") {
                    showRevokeAlert = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(PLColor.danger)
            }
        }
    }

    private var trophiesSection: some View {
        VStack(spacing: PLSpacing.sm) {
            PLSectionHeader(title: "Trophies")
            Group {
                if friendTrophies.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "trophy")
                            .font(.title2)
                            .foregroundColor(PLColor.textSecondary)
                        Text("No trophies yet")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PLSpacing.md)
                } else {
                    LazyVGrid(columns: columns, spacing: PLSpacing.md) {
                        ForEach(friendTrophies) { trophy in
                            VStack(spacing: 6) {
                                Image(trophyImageName(for: trophy))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 56, height: 56)
                                Text(trophy.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(trophyColor(for: trophy.level))
                                    .multilineTextAlignment(.center)
                            }
                            .onTapGesture {
                                withAnimation { selectedTrophy = trophy }
                            }
                        }
                    }
                }
            }
            .plCard()
        }
    }

    private var inviteSheet: some View {
        NavigationStack {
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
                            .tint(PLColor.accent)
                    }
                }
            }
            .navigationBarTitle("Share My Calendar", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { showInviteSheet = false },
                trailing: Button("Send") {
                    calendarVM.sendCalendarInvite(to: username, level: inviteLevel, requireApproval: inviteRequireApproval)
                    showInviteSheet = false
                }.bold()
            )
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
                AppBanner.report("load \(username)'s profile", error, retry: { fetchFriendProfile() })
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
