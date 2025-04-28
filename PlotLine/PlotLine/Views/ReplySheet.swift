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
                        .font(.subheadline).bold()
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Existing replies
                if message.replies.isEmpty {
                    Text("No replies yet")
                        .italic()
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
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
                                                    .bold()
                                                    .foregroundColor(.blue)
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
                HStack {
                    TextField("Your reply…", text: $text)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Send") {
                        Task {
                            await vm.reply(to: message, text: text)
                            dismiss()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .navigationTitle("Replies")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedUser) { user in
                FriendProfileView(username: user)
                    .environmentObject(friendsVM)
            }
        }
    }
}

