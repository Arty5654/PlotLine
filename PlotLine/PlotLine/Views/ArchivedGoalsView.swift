import SwiftUI

struct ArchivedGoalsView: View {
    @Binding var archivedGoals: [LongTermGoal]
    @Environment(\.dismiss) var dismiss

    var unarchiveGoal: (LongTermGoal) -> Void
    var shareGoalToFriends: (LongTermGoal) -> Void
    
    /* Fetch the logged-in username from UserDefaults */
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(archivedGoals) { goal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(goal.title)
                                .font(.headline)
                            
                            Spacer()
                            
                            Menu {
                                Button(action: {
                                    unarchiveGoal(goal)
                                }) {
                                    Label("Unarchive", systemImage: "arrow.uturn.left")
                                }
                                
                                Button(action: {
                                    shareGoalToFriends(goal)
                                }) {
                                    Label("Share to Friends", systemImage: "person.3.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                            }

                        }
                        
                        ForEach(goal.steps) { step in
                            Text("- \(step.name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Archived Goals")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            fetchArchivedGoals()
        }
    }
    
    private func fetchArchivedGoals() {
        guard username != "Guest",
              let url = URL(string: "http://localhost:8080/api/goals/\(username)/long-term") else {
            print("⚠️ Invalid username or URL")
            return
        }
        
        print("📡 Fetching archived goals from: \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("⚠️ No data received from backend")
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(LongTermGoalsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.archivedGoals = decodedResponse.archivedGoals ?? []
                    print("✅ Successfully loaded \(self.archivedGoals.count) archived goals")
                }
            } catch {
                print("❌ Error decoding archived goals JSON: \(error)")
            }
        }.resume()
    }
    
}


