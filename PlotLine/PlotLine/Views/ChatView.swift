import SwiftUI

struct ChatView: View {
    @EnvironmentObject var vm: ChatViewModel
    @State private var reactingTo: ChatMessage?
    @State private var replyingTo: ChatMessage?

    private let allEmojis = ["👍","❤️","😂","🎉","😮","😢"]

    var body: some View {
        VStack {
            List {
                ForEach(vm.messages) { msg in
                    ChatMessageRow(
                        msg: msg,
                        allEmojis: allEmojis,
                        onReactTap: { reactingTo = msg },
                        onReplyTap: { replyingTo = msg }
                    )
                    .environmentObject(vm)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 4)                // small gap between cards
                }
            }
            .listStyle(.plain)                          // plain style

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
        .onAppear { Task { await vm.load() } }
        .sheet(item: $reactingTo) { msg in
            let used = Set(msg.reactions.keys)
            EmojiPickerView(emojis: allEmojis.filter { !used.contains($0) }) { emoji in
                Task { await vm.react(to: msg, emoji: emoji) }
                reactingTo = nil
            }
        }
        .sheet(item: $replyingTo) { msg in
            ReplySheet(message: msg)
                .environmentObject(vm)
        }
    }
}
