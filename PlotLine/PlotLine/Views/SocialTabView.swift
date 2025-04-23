import SwiftUI

struct SocialTabView: View {
    @EnvironmentObject var friendsVM: FriendsViewModel
    @EnvironmentObject var chatVM: ChatViewModel

    @State private var selection: Tab = .friends
    enum Tab { case friends, chat, third }

    var body: some View {
        TabView(selection: $selection) {
            // — Friends tab —
            NavigationStack {
                FriendsView()
                    .environmentObject(friendsVM)
                    .navigationTitle("My Friends")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Image(systemName: "person.2.fill") }
            .tag(Tab.friends)

            // — Chat tab —
            NavigationStack {
                ChatView()
                    .environmentObject(chatVM)
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Image(systemName: "bubble.left.and.bubble.right.fill") }
            .tag(Tab.chat)

            // — More tab —
            NavigationStack {
                ThirdView()
                    .navigationTitle("More")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Image(systemName: "ellipsis.circle.fill") }
            .tag(Tab.third)
        }
        .accentColor(.blue)
    }
}


// Placeholder for @allen's tab
struct ThirdView: View {
    var body: some View {
        VStack {
            Text("Coming Soon")
                .font(.title)
                .foregroundColor(.gray)
        }
    }
}
