import SwiftUI

struct ChatView: View {
    @EnvironmentObject var vm: ChatViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel
    @State private var reactingTo: ChatMessage?
    @State private var replyingTo: ChatMessage?

    private let allEmojis = ["👍","❤️","😂","🎉","😮","😢","😡","🔥","👏","🙏","🤔","😍","😭","😎","🙌","💯","🤯","👎","🥳","🤗",
                             "😤","😳","😆","🤩","😬","😇","💔","👀","🍀","🫶","🧡","💥","😴","🫠","😐","😜","🎯","🫢"]

    var body: some View {
        VStack {
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
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

            HStack {
                TextField("Type a message…", text: $vm.draft)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Send") {
                    Task { await vm.send() }
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
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
