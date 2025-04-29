import SwiftUI

struct ArchivedGoalsView: View {
    @Binding var archivedGoals: [LongTermGoal]
    @Environment(\.dismiss) var dismiss

    var unarchiveGoal: (LongTermGoal) -> Void
    
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
                                    // Placeholder for share to friends action
                                    print("Share \(goal.title) to friends")
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
    }
}


