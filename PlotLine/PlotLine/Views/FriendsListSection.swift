import SwiftUI

struct FriendsListSection: View {
    let friends: [String]
    let onSelect: (String) -> Void
    
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
                                .foregroundColor(Color(red: 0.0, green: 0.0, blue: 0.5)) // navy blue
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
