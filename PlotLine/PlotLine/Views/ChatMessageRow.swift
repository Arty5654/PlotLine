import SwiftUI

struct ChatMessageRow: View {
    @EnvironmentObject var vm: ChatViewModel

    let msg: ChatMessage
    let currentUsername: String
    let allEmojis: [String]
    let onReactTap: () -> Void
    let onReplyTap: ()  -> Void

    private var isMine: Bool { msg.creator == currentUsername }
    private var replyCount: Int { msg.replies.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Tappable content area — opens reply thread
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    FriendProfilePicture(username: msg.creator)
                        .frame(width: 26, height: 26)
                    Text(isMine ? "You" : msg.creator)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(msg.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                }

                Text(msg.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if !msg.reactions.isEmpty {
                    ReactionBubbles(message: msg)
                        .environmentObject(vm)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onReplyTap() }

            HStack(spacing: 20) {
                Button(action: onReactTap) {
                    Image(systemName: "face.smiling")
                }
                .accessibilityLabel("React")

                Button(action: onReplyTap) {
                    Label(replyCount == 0 ? "Reply" : "\(replyCount) \(replyCount == 1 ? "reply" : "replies")",
                          systemImage: "arrowshape.turn.up.left")
                        .font(.footnote)
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            .foregroundColor(PLColor.textSecondary)
        }
        .padding(PLSpacing.md)
        .background(isMine ? PLColor.accent.opacity(0.12) : PLColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
