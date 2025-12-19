import SwiftUI

struct LongTermGoalsView: View {
    @Binding var longTermGoals: [LongTermGoal]
    @Binding var newLongTermTitle: String
    @Binding var newStep: String
    @Binding var newLongTermSteps: [String]
    let username: String 

    @State private var archivedGoals: [LongTermGoal] = []
    @State private var showArchiveSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Creation Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Create a Long-Term Goal")
                        .font(.headline)

                    TextField("Enter goal title", text: $newLongTermTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    HStack {
                        TextField("Enter a step", text: $newStep)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            guard !newStep.isEmpty else { return }
                            newLongTermSteps.append(newStep)
                            newStep = ""
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }

                    if !newLongTermSteps.isEmpty {
                        Text("Steps:")
                            .font(.subheadline)
                            .bold()

                        ForEach(newLongTermSteps, id: \.self) { step in
                            Text("• \(step)")
                        }
                    }

                    Button(action: addLongTermGoal) {
                        Text("Save Goal")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(10)
                    }

                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                

                // Display Section
                if !longTermGoals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(longTermGoals) { goal in
                            VStack(alignment: .leading, spacing: 6) {
                                // Long Term goal title
                                HStack (){
                                    Text(goal.title)
                                        .font(.title3)
                                        .bold()
                                    Spacer()
                                    Button(action: {
                                        archiveGoal(goal)
                                    }) {
                                        Image(systemName: "archivebox")
                                            .foregroundColor(.blue)
                                            .font(.title2)
                                    }
                                }.padding(.bottom, 8)
                                
                      

                                // Step List
                                ForEach(goal.steps) { step in
                                    HStack {
                                        Text(step.name)
                                            .strikethrough(step.isCompleted)
                                            .foregroundColor(step.isCompleted ? .gray : .primary)

                                        Spacer()

                                        Button(action: {
                                            toggleLongStepCompletion(goalId: goal.id, stepId: step.id)
                                        }) {
                                            Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(step.isCompleted ? .green : .gray)
                                                .font(.title2)
                                        }
                                    }
                                }

                                // Progress Bar
                                let completedSteps = goal.steps.filter { $0.isCompleted }.count
                                let totalSteps = goal.steps.count
                                let progress = totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : 0

                                ProgressView(value: progress)
                                    .accentColor(.green)
                                    .padding(.top, 4)

                                Text("\(Int(progress * 100))% completed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Divider() // Divider between goals
                            }
                            .padding(.top, 8)
                        }

                    }
                    .padding(.horizontal)
                }
            }
        }
        
        // Reset button
        Button(action: resetLongTermGoals) {
            Text("Reset Long-Term Goals")
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .cornerRadius(10)
                .padding()
        }
        
        // Archive button
        Button(action: {
            showArchiveSheet = true
        }) {
            Text("View Archived Goals")
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .sheet(isPresented: $showArchiveSheet) {
            ArchivedGoalsView(
                archivedGoals: $archivedGoals,
                unarchiveGoal: { goal in
                    unarchiveGoal(goal)
                },
                shareGoalToFriends: { goal in
                    shareGoalToFriends(goal: goal)
                }
            )
        }

    }
    
    

    
    private func archiveGoal(_ goal: LongTermGoal) {
        // Remove from active goals
        longTermGoals.removeAll { $0.id == goal.id }
        archivedGoals.append(goal)
        
        // Send archive request to backend
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/\(goal.id)/archive") else {
            print("❌ Invalid URL for archiving goal")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Archive network error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📦 Archive goal status code: \(httpResponse.statusCode)")
            }
        }.resume()
    }
    
    private func unarchiveGoal(_ goal: LongTermGoal) {
        archivedGoals.removeAll { $0.id == goal.id }
        longTermGoals.append(goal)
        
        // Send unarchive request to backend
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/\(goal.id)/unarchive") else {
            print("❌ Invalid URL for unarchiving goal")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Unarchive network error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📦 Unarchive goal status code: \(httpResponse.statusCode)")
            }
        }.resume()
    }


    
    private func addLongTermGoal() {
        guard !newLongTermTitle.isEmpty else { return }
        
        let newGoal = LongTermGoal(
            id: UUID(),
            title: newLongTermTitle,
            steps: newLongTermSteps.map {
                LongTermStep(id: UUID(), name: $0, isCompleted: false)
            }
        )
        
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term") else {
            print("❌ Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(newGoal)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding long-term goal JSON: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Long Term Goals: 🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            DispatchQueue.main.async {
                self.longTermGoals.append(newGoal)
                self.newLongTermTitle = ""
                self.newLongTermSteps = []
            }
        }.resume()
    }
    
    private func toggleLongStepCompletion(goalId: UUID, stepId: UUID) {
        guard let goalIndex = longTermGoals.firstIndex(where: { $0.id == goalId }),
              let stepIndex = longTermGoals[goalIndex].steps.firstIndex(where: { $0.id == stepId }) else { return }
        
        // Toggle local state
        longTermGoals[goalIndex].steps[stepIndex].isCompleted.toggle()
        
        // Prepare backend update
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/\(goalId)/steps/\(stepId)") else {
            print("❌ Invalid URL for step update")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["isCompleted": longTermGoals[goalIndex].steps[stepIndex].isCompleted]
        
        do {
            let jsonData = try JSONEncoder().encode(payload)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding step completion update: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Step completion update status code: \(httpResponse.statusCode)")
            }
        }.resume()
    }
    
    private func resetLongTermGoals() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/\(username)/long-term/reset") else {
            print("❌ Invalid URL for resetting long-term goals")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            DispatchQueue.main.async {
                self.longTermGoals.removeAll() // Clear the UI
            }
        }.resume()
    }
    
    /* Check of steps in a long term goal*/
    private func toggleStepCompletion(goalId: UUID, stepId: UUID) {
        if let goalIndex = longTermGoals.firstIndex(where: { $0.id == goalId }) {
            if let stepIndex = longTermGoals[goalIndex].steps.firstIndex(where: { $0.id == stepId }) {
                longTermGoals[goalIndex].steps[stepIndex].isCompleted.toggle()
            }
        }
    }
    
    /* Sharing an archived post*/
    private func shareGoalToFriends(goal: LongTermGoal) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post") else {
            print("❌ Invalid share URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let friendPost = FriendPost(
            id: UUID(),
            username: username,
            goal: goal,
            comment: nil
        )

        do {
            let jsonData = try JSONEncoder().encode(friendPost)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding FriendPost: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Share network error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🚀 Share post status code: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    
}

//#Preview {
//    LongTermGoalsView(
//        longTermGoals: .constant([]),
//        newLongTermTitle: .constant(""),
//        newStep: .constant(""),
//        newLongTermSteps: .constant([]),
//        username: "PreviewUser"
//    )
//}
