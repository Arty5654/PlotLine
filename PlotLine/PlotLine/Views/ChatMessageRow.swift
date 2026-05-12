import SwiftUI

struct ChatMessageRow: View {
    @EnvironmentObject var vm: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    let msg: ChatMessage
    let currentUsername: String
    let allEmojis: [String]
    let onReactTap: () -> Void
    let onReplyTap: ()  -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Tappable content area — opens reply thread
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(msg.creator == currentUsername ? "\(msg.creator) (Me)" : msg.creator).bold()
                    Spacer()
                    Text(msg.timestamp, style: .time)
                        .font(.caption)
                }

                Text(msg.content)
                    .font(.body)

                if !msg.reactions.isEmpty {
                    ReactionBubbles(message: msg)
                        .environmentObject(vm)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onReplyTap() }

            HStack(spacing: 24) {
                Button(action: onReactTap) {
                    Image(systemName: "face.smiling")
                }
                .buttonStyle(BorderlessButtonStyle())

                Button(action: onReplyTap) {
                    Image(systemName: "arrowshape.turn.up.left\(msg.replies.isEmpty ? "" : ".fill")")
                        .foregroundColor(msg.replies.isEmpty ? .primary : adaptiveTextColor)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: Color.black.opacity(0.1),
                radius: 4, x: 0, y: 2)
    }
}
