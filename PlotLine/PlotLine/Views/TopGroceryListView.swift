import SwiftUI

struct TopGroceryListView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                MealsView()
                    .tabItem { Label("Meals", systemImage: "fork.knife.circle") }
                    .tag(0)

                ActiveGroceryListView()
                    .tabItem { Label("Active Lists", systemImage: "list.dash") }
                    .tag(1)

                ArchivedGroceryListsView(username: UserDefaults.standard.string(forKey: "loggedInUsername") ?? "")
                    .tabItem { Label("Archived", systemImage: "archivebox") }
                    .tag(2)
            }
            .navigationTitle("Grocery")
        }
    }
}
