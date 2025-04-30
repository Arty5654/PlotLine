import SwiftUI

struct TopGroceryListView: View {
    @State private var selectedTab = 0  // State to control the TabView selection (0 = Active, 1 = Archived)

    var body: some View {
        NavigationView {
            VStack {
                // Tab View for navigating between the active grocery lists and archived grocery lists
                TabView(selection: $selectedTab) {
                    // Meals Tab
                    MealsView()
                        .tabItem {
                            Image(systemName: "fork.knife.circle")
                            Text("Meals")
                        }
                        .tag(0)
                    
                    // Active Grocery List Tab
                    ActiveGroceryListView()
                        .tabItem {
                            Image(systemName: "list.dash")
                            Text("Active Lists")
                        }
                        .tag(1)

                    // Archived Grocery List Tab
                    ArchivedGroceryListsView(username: UserDefaults.standard.string(forKey: "loggedInUsername") ?? "")
                        .tabItem {
                            Image(systemName: "archivebox")
                            Text("Archived Lists")
                        }
                        .tag(2)
                }
            }
            .navigationTitle("Nutrition")
        }
    }
}
