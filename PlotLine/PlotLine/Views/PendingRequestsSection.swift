import SwiftUI

struct PendingRequestsSection: View {
    let pendingRequests: [String]
    let currentUsername: String
    let onSelect: (String) -> Void
    let onAccept: (String) async -> Void
    let onDecline: (String) async -> Void

    var body: some View {
        VStack(spacing: PLSpacing.sm) {
            PLSectionHeader(title: "Friend Requests")

            if pendingRequests.isEmpty {
                Text("No pending requests.")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pendingRequests.enumerated()), id: \.element) { index, senderUsername in
                        if index > 0 { Divider().padding(.leading, 48) }
                        HStack(spacing: 12) {
                            Button { onSelect(senderUsername) } label: {
                                HStack(spacing: 12) {
                                    FriendProfilePicture(username: senderUsername)
                                        .frame(width: 36, height: 36)
                                    Text(senderUsername)
                                        .foregroundColor(PLColor.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .layoutPriority(1)

                            Spacer(minLength: 8)

                            Button("Accept") {
                                Task { await onAccept(senderUsername) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PLColor.success)
                            .controlSize(.small)

                            Button("Decline") {
                                Task { await onDecline(senderUsername) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .plCard()
            }
        }
    }
}
