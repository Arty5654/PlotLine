//
//  InvestmentQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI

import SwiftUI

struct InvestmentQuizView: View {
    @State private var goals = ""
    @State private var riskTolerance = ""
    @State private var investingExperience = ""
    @State private var age = ""
    @State private var quizCompleted = false
    @State private var llmRecommendation: String? = nil
    @Environment(\.dismiss) var dismiss

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
                        TextField("e.g., Retirement, Wealth Growth", text: $goals)
                    }
                    Section(header: Text("Risk Tolerance")) {
                        TextField("e.g., Low, Medium, High", text: $riskTolerance)
                    }
                    Section(header: Text("Investing Experience")) {
                        TextField("e.g., Beginner, Intermediate, Advanced", text: $investingExperience)
                    }
                    
                    Section(header: Text("Age")) {
                        TextField("Input age", text: $age)
                    }

                    Button("Submit Quiz") {
                        quizCompleted = true
                    }
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
        }.resume()
    }

}




#Preview {
    InvestmentQuizView()
}
