import SwiftUI

struct ReplySheet: View {
    @EnvironmentObject private var vm: ChatViewModel
    @EnvironmentObject private var friendsVM: FriendsViewModel
    @Environment(\.dismiss) private var dismiss

    let message: ChatMessage
    @State private var text = ""
    @State private var selectedUser: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                
                // Original message
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.creator)
                        .font(.subheadline.weight(.semibold))
                    Text(message.content)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .plCard()

                PLSectionHeader(title: "Replies")

                // Existing replies
                if message.replies.isEmpty {
                    Text("No replies yet. Be the first.")
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(message.replies.keys.sorted(), id: \.self) { user in
                                if let replies = message.replies[user] {
                                    ForEach(replies, id: \.self) { reply in
                                        HStack(alignment: .top, spacing: 8) {
                                            Button(action: {
                                                selectedUser = user
                                            }) {
                                                Text(user)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(PLColor.tint)
                                            }
                                            Text(reply)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }

                Spacer()

                // New reply input
                HStack(spacing: 10) {
                    TextField("Your reply…", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(PLColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    Button {
                        Task {
                            if await vm.reply(to: message, text: text) { dismiss() }
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(PLColor.accent)
                            .clipShape(Circle())
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Send reply")
                }
            }
            .padding(PLSpacing.lg)
            .navigationTitle("Replies")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedUser) { user in
                FriendProfileView(username: user)
                    .environmentObject(friendsVM)
            }
        }
    }
}

