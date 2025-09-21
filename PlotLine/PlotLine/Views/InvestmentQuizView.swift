//
//  InvestmentQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI
import Foundation

struct InvestmentQuizView: View {
    enum InvestmentAccount: String, CaseIterable, Identifiable {
        case brokerage = "Brokerage"
        case rothIRA = "Roth IRA"
        var id: String { rawValue }
        var apiValue: String { self == .brokerage ? "BROKERAGE" : "ROTH_IRA" }
    }

    @State private var selectedAccount: InvestmentAccount = .brokerage

    @State private var goals = ""
    @State private var riskTolerance = ""
    @State private var investingExperience = ""
    @State private var age = ""
    @State private var quizCompleted = false
    @State private var llmRecommendation: String? = nil
    @Environment(\.dismiss) var dismiss
    
    // Check for Missing Budget
    @State private var showBudgetMissingAlert = false
    @State private var budgetMissingMessage = ""
    
    // Sometimes pie chart wont refresh
    var onFinish: (() -> Void)? = nil


    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    // For Calander
    @EnvironmentObject var calendarViewModel: CalendarViewModel

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
                        onFinish?()
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
                    Section(header: Text("Account")) {
                        Picker("Account", selection: $selectedAccount) {
                            ForEach(InvestmentAccount.allCases) { acct in
                                Text(acct.rawValue).tag(acct)
                            }
                        }
                        .pickerStyle(.segmented)

                        if selectedAccount == .rothIRA {
                            Text("We’ll create a Roth IRA portfolio. The monthly amount will be taken from your **Budget → “Roth IRA”** line if available; otherwise we’ll fall back to your income.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            Text("We’ll create a standard brokerage portfolio. The monthly amount will be taken from **Budget → “Other Investments”** if available; otherwise we’ll fall back to your income.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

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
        // Pop an alert if user has no budget for investments
        .alert("Add to Budget First", isPresented: $showBudgetMissingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(budgetMissingMessage)
        }
}
    
    // Verify budget contains the required category with a positive amount
    private func precheckBudgetLine() async -> Bool {
        guard let url = URL(string: "http://localhost:8080/api/budget/\(username)/monthly") else {
            budgetMissingMessage = "Could not check your Budget. Please ensure your Budget includes the needed line."
            showBudgetMissingAlert = true
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
                // Treat no budget as missing
                let key = (selectedAccount == .rothIRA) ? "Roth IRA" : "Brokerage"
                budgetMissingMessage = "We couldn’t find your Budget. Please create a budget and add a “\(key)” line first."
                showBudgetMissingAlert = true
                return false
            }

            struct BudgetResponse: Decodable {
                let budget: [String: Double]
            }

            if let decoded = try? JSONDecoder().decode(BudgetResponse.self, from: data) {
                let key = (selectedAccount == .rothIRA) ? "Roth IRA" : "Brokerage"
                if let val = decoded.budget[key], val > 0 {
                    return true
                } else {
                    budgetMissingMessage = "To build a \(selectedAccount.rawValue) portfolio, please add a monthly amount for “\(key)” in your Budget first."
                    showBudgetMissingAlert = true
                    return false
                }
            } else {
                // Fallback: try flat map (in case backend returns a plain {category: amount} map)
                if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let key = (selectedAccount == .rothIRA) ? "Roth IRA" : "Brokerage"
                    if let val = map[key] as? Double, val > 0 {
                        return true
                    }
                }
                let key = (selectedAccount == .rothIRA) ? "Roth IRA" : "Brokerage"
                budgetMissingMessage = "Please add a monthly amount for “\(key)” in your Budget first."
                showBudgetMissingAlert = true
                return false
            }
        } catch {
            let key = (selectedAccount == .rothIRA) ? "Roth IRA" : "Brokerage"
            budgetMissingMessage = "Couldn’t reach the Budget service. Make sure your Budget has a “\(key)” line, then try again."
            showBudgetMissingAlert = true
            return false
        }
    }

    func generatePortfolioFromLLM() async {
        let url = URL(string: "http://localhost:8080/api/llm/portfolio")!
        let payload: [String: String] = [
            "username": username,
            "goals": goals,
            "riskTolerance": riskTolerance,
            "experience": investingExperience,
            "age": age,
            "account": selectedAccount.apiValue
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
                savePortfolioToBackend(response)
            }
        } catch {
            print("Error generating portfolio from LLM.")
            dismiss()
        }
    }


    func savePortfolioToBackend(_ recommendation: String) {
        let url = URL(string: "http://localhost:8080/api/llm/portfolio/save-original")!
        let payload: [String: String] = [
            "username": username,
            "portfolio": recommendation,
            "riskTolerance": riskTolerance,
            "account": selectedAccount.apiValue
        ]

        print("Risk after quiz completion: " + riskTolerance)

        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("Portfolio saved to backend.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task {
                    calendarViewModel.addMonthlyInvestmentReminder(dayOfMonth: 1)
                }
                onFinish?()  // Notifies StockView to refresh and pops view
                dismiss()    // Navigates back
            }

        }.resume()
    }


}


#Preview {
    InvestmentQuizView()
}
