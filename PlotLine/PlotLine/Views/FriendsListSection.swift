import SwiftUI

struct FriendsListSection: View {
    let friends: [String]
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            if friends.isEmpty {
                Text("No friends yet.")
                    .font(.custom("AvenirNext-Bold", size: 16))
                    .foregroundColor(.gray)
                    .italic()
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(friends, id: \.self) { friend in
                    Button {
                        onSelect(friend)
                    } label: {
                        HStack {
                            Text(friend)
                                .font(.custom("AvenirNext-Bold", size: 16))
                                .foregroundColor(adaptiveTextColor)
                            Spacer()
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
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}
