import SwiftUI

struct FriendsListSection: View {
    let friends: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: PLSpacing.sm) {
            PLSectionHeader(title: friends.isEmpty ? "Friends" : "Friends (\(friends.count))")

            if friends.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.title2)
                        .foregroundColor(PLColor.textSecondary)
                    Text("No friends yet")
                        .font(.headline)
                    Text("Tap + to find people, or share your invite link.")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .plCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(friends.enumerated()), id: \.element) { index, friend in
                        if index > 0 { Divider().padding(.leading, 48) }
                        Button { onSelect(friend) } label: {
                            HStack(spacing: 12) {
                                FriendProfilePicture(username: friend)
                                    .frame(width: 36, height: 36)
                                Text(friend)
                                    .foregroundColor(PLColor.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .plCard()
            }
        }
    }
}
