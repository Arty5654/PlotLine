import SwiftUI

struct ChatView: View {
    @EnvironmentObject var vm: ChatViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel
    @State private var reactingTo: ChatMessage?
    @State private var replyingTo: ChatMessage?

    private let allEmojis = ["👍","❤️","😂","🎉","😮","😢","😡","🔥","👏","🙏","🤔","😍","😭","😎","🙌","💯","🤯","👎","🥳","🤗",
                             "😤","😳","😆","🤩","😬","😇","💔","👀","🍀","🫶","🧡","💥","😴","🫠","😐","😜","🎯","🫢"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.messages.reversed()) { msg in
                            ChatMessageRow(
                                msg: msg,
                                currentUsername: vm.username,
                                allEmojis: allEmojis,
                                onReactTap: { reactingTo = msg },
                                onReplyTap: { replyingTo = msg }
                            )
                            .environmentObject(vm)
                            .id(msg.id)
                            .padding(.horizontal, PLSpacing.lg)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.messages.count) {
                    if let newest = vm.messages.first {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(newest.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let newest = vm.messages.first {
                        proxy.scrollTo(newest.id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Message your friends…", text: $vm.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PLColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(PLColor.accent)
                        .clipShape(Circle())
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.sm)
        }
        .navigationTitle("Chat")
        .task {
            await vm.load()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // refresh every 2s while on page
                await vm.load()
            }
        }
        .sheet(item: $reactingTo) { msg in
            EmojiPickerView(emojis: allEmojis) { emoji in
                Task { await vm.react(to: msg, emoji: emoji) }
                reactingTo = nil
            }
        }
        .sheet(item: $replyingTo) { msg in
            ReplySheet(message: msg)
                .environmentObject(vm)
                .environmentObject(friendsVM)
        }
    }
}
