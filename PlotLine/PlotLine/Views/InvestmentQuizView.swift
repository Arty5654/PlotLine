//
//  InvestmentQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI

struct InvestmentQuizView: View {
    @State private var goals = ""
    @State private var riskTolerance = ""
    @State private var investingExperience = ""
    @State private var age = ""
    @State private var quizCompleted = false
    @State private var llmRecommendation: String? = nil
    @Environment(\.dismiss) var dismiss
    
    // Sometimes pie chart wont refresh
    var onFinish: (() -> Void)? = nil


    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack {
            if let recommendation = llmRecommendation {
                ScrollView {
                    Text("Your AI-Powered Portfolio")
                        .font(.title2)
                        .bold()
                        .padding(.bottom)

                    Text(recommendation)
                        .font(.body)
                        .padding()

                    Button("Back to Stocks Page") {
                        //onFinish?()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if quizCompleted {
                ProgressView("Generating portfolio...")
                    .task {
                        await generatePortfolioFromLLM()
                    }
            } else {
                Form {
                    Section(header: Text("Investment Goals")) {
                        Picker("Goal", selection: $goals) {
                            Text("Retirement").tag("Retirement")
                            Text("Wealth Growth").tag("Wealth Growth")
                            Text("Education").tag("Education")
                            Text("Buying a Home").tag("Buying a Home")
                        }
                        .pickerStyle(.inline)
                    }

                    Section(header: Text("Risk Tolerance")) {
                        Picker("Risk Tolerance", selection: $riskTolerance) {
                            Text("Low").tag("Low")
                            Text("Medium").tag("Medium")
                            Text("High").tag("High")
                        }
                        .pickerStyle(.segmented)
                    }

                    Section(header: Text("Investing Experience")) {
                        Picker("Experience", selection: $investingExperience) {
                            Text("Beginner").tag("Beginner")
                            Text("Intermediate").tag("Intermediate")
                            Text("Advanced").tag("Advanced")
                        }
                        .pickerStyle(.inline)
                    }

                    Section(header: Text("Age")) {
                        TextField("Enter your age", text: $age)
                            .keyboardType(.numberPad)
                    }

                    Button("Submit Quiz") {
                        quizCompleted = true
                    }
                    .disabled(goals.isEmpty || riskTolerance.isEmpty || investingExperience.isEmpty || age.isEmpty)
                }
            }
        }
        .padding()
        .navigationTitle("Investor Quiz")
}

    func generatePortfolioFromLLM() async {
        let url = URL(string: "http://localhost:8080/api/llm/portfolio")!
        let payload: [String: String] = [
            "username": username,
            "goals": goals,
            "riskTolerance": riskTolerance,
            "experience": investingExperience,
            "age": age
        ]
        print("Username: " + username)

        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let response = String(data: data, encoding: .utf8) {
                llmRecommendation = response
                savePortfolioToBackend(response)
            }
            
        } catch {
            llmRecommendation = "Error getting portfolio from LLM."
        }
    }

    func savePortfolioToBackend(_ recommendation: String) {
        let url = URL(string: "http://localhost:8080/api/llm/portfolio/save-original")!
        let payload: [String: String] = [
            "username": username,
            "portfolio": recommendation,
            "riskTolerance": riskTolerance
        ]
        
        print("Risk after quiz completion: " + riskTolerance)

        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("Portfolio saved to backend.")
            
//            DispatchQueue.main.async {
//                onFinish?()
//            }
        }.resume()

    }

}




#Preview {
    InvestmentQuizView()
}
