import SwiftUI

struct PendingRequestsSection: View {
    let pendingRequests: [String]
    let currentUsername: String
    let onSelect: (String) -> Void
    let onAccept: (String) async -> Void
    let onDecline: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            Text("Pending Friend Requests")
                .font(.custom("AvenirNext-Bold", size: 16))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            
            if pendingRequests.isEmpty {
                Text("No pending requests.")
                    .font(.custom("AvenirNext-Bold", size: 13))
                    .foregroundColor(.gray)
                    .italic()
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                
                ForEach(pendingRequests, id: \.self) { senderUsername in
                    HStack(spacing: 12) {
                        Button {
                            onSelect(senderUsername)
                        } label: {
                            Text(senderUsername)
                                .font(.custom("AvenirNext-Bold", size: 16))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Button("Accept") {
                            Task {
                                await onAccept(senderUsername)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Decline") {
                            Task {
                                await onDecline(senderUsername)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}
