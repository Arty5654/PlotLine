//
//  InvestmentQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let danger         = Color.red
    static let warning        = Color.orange
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius {
    static let md: CGFloat = 12
}
private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(PLColor.cardBorder)
            )
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}



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
    @State private var timeHorizon = ""
    @State private var taxPriority = ""
    @State private var withdrawalFlexibility = ""
    @State private var age = ""
    @State private var quizCompleted = false
    @State private var llmRecommendation: String? = nil
    @Environment(\.dismiss) var dismiss
    @State private var monthlyContribution: Double = 0
    
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
    
    private func optionRow(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
    
    private func pickerLabel(title: String, value: String, placeholder: String) -> some View {
        HStack(spacing: PLSpacing.sm) {
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value.isEmpty ? placeholder : value)
                .foregroundColor(.primary)
            
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(PLColor.accent)
        }
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
                ScrollView {
                    VStack(spacing: PLSpacing.lg) {
                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Account")
                                .font(.headline)
                            
                            Picker("Account", selection: $selectedAccount) {
                                ForEach(InvestmentAccount.allCases) { acct in
                                    Text(acct.rawValue).tag(acct)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(selectedAccount == .rothIRA ?
                                 "We’ll create a Roth IRA portfolio. The monthly amount will be taken from your Budget → “Roth IRA” line if available; otherwise we’ll fall back to your income." :
                                    "We’ll create a standard brokerage portfolio. The monthly amount will be taken from Budget → “Other Investments” if available; otherwise we’ll fall back to your income.")
                            .font(.footnote)
                            .foregroundColor(PLColor.textSecondary)
                        }
                        .plCard()

                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Investment Goals")
                                .font(.headline)
                            
                            Picker(selection: $goals) {
                                optionRow("Retirement", isSelected: goals == "Retirement").tag("Retirement")
                                optionRow("Wealth Growth", isSelected: goals == "Wealth Growth").tag("Wealth Growth")
                                optionRow("Education", isSelected: goals == "Education").tag("Education")
                                optionRow("Buying a Home", isSelected: goals == "Buying a Home").tag("Buying a Home")
                            } label: {
                                HStack {
                                    Text("Select Goal")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(PLColor.accent)
                            }
                            .pickerStyle(.navigationLink)
                        }
                        .plCard()

                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Risk Tolerance")
                                .font(.headline)
                            Text("How comfortable are you with big ups and downs in your investments?")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)

                            Picker("", selection: $riskTolerance) {
                                Text("Low").tag("Low")
                                Text("Medium").tag("Medium")
                                Text("High").tag("High")
                            }
                            .pickerStyle(.segmented)
                        }
                        .plCard()

                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Investing Experience")
                                .font(.headline)
                            Text("How would you describe your investing experience?")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)

                            Picker("", selection: $investingExperience) {
                                Text("Beginner").tag("Beginner")
                                Text("Intermediate").tag("Intermediate")
                                Text("Advanced").tag("Advanced")
                            }
                            .pickerStyle(.segmented)
                        }
                        .plCard()

                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Time Horizon")
                                .font(.headline)
                            Text("Roughly how long until you expect to use this money?")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)

                            Picker("", selection: $timeHorizon) {
                                Text("0–5 years").tag("0–5 years")
                                Text("5–15 years").tag("5–15 years")
                                Text("15+ years").tag("15+ years")
                            }
                            .pickerStyle(.segmented)

                            Text("Roth IRAs are generally best for long-term retirement money, while brokerage accounts can work for shorter goals.")
                                .font(.footnote)
                                .foregroundColor(PLColor.textSecondary)
                        }
                        .plCard()

                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Tax vs. Flexibility")
                                .font(.headline)
                            Text("What matters more to you?")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)
                            
                            Picker(selection: $taxPriority) {
                                optionRow("Minimize taxes, even if money is locked up", isSelected: taxPriority == "Tax Efficiency").tag("Tax Efficiency")
                                optionRow("Max flexibility, even if I pay more taxes", isSelected: taxPriority == "Flexibility").tag("Flexibility")
                                optionRow("Balanced between taxes and flexibility", isSelected: taxPriority == "Balanced").tag("Balanced")
                            } label: {
                                HStack {
                                    Text("Select Preference")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(PLColor.accent)
                            }
                            .pickerStyle(.navigationLink)
                        }
                        .plCard()

                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            Text("Withdrawal Flexibility")
                                .font(.headline)
                            Text("How likely are you to need this money before retirement?")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)
                            
                            Picker(selection: $withdrawalFlexibility) {
                                optionRow("Very unlikely – this is long-term", isSelected: withdrawalFlexibility == "Very Unlikely").tag("Very Unlikely")
                                optionRow("Possibly – I might need some", isSelected: withdrawalFlexibility == "Possible").tag("Possible")
                                optionRow("Likely – I may tap this within a few years", isSelected: withdrawalFlexibility == "Likely").tag("Likely")
                            } label: {
                                HStack {
                                    Text("Select Preference")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(PLColor.accent)
                            }
                            .pickerStyle(.navigationLink)
                            
                            Text("Roth IRAs have a withdrawal penalty of 10% if money is taken before age 59.5 or the account is less than five years old.")
                                .font(.footnote)
                                .foregroundColor(PLColor.textSecondary)
                        }
                        .plCard()

                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Age")
                        .font(.headline)
                    TextField("Enter your age", text: $age)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                .plCard()

                        VStack(spacing: PLSpacing.sm) {
                            Button("Submit Quiz") {
                                Task {
                                    let ok = await precheckBudgetLine()
                                    if ok {
                                        await MainActor.run { quizCompleted = true }
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButton())
                            .disabled(
                                goals.isEmpty ||
                                riskTolerance.isEmpty ||
                                investingExperience.isEmpty ||
                                age.isEmpty ||
                                timeHorizon.isEmpty ||
                                taxPriority.isEmpty ||
                                withdrawalFlexibility.isEmpty
                            )
                        }
                    }
                    .padding(.horizontal, PLSpacing.lg)
                    .padding(.vertical, PLSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { hideKeyboard() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Investor Quiz").font(.headline)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .tint(PLColor.accent)
        .alert("Add to Budget First", isPresented: $showBudgetMissingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(budgetMissingMessage)
        }
    }

    private func hideKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
    
    // Verify budget contains the required category with a positive amount
    private func precheckBudgetLine() async -> Bool {
        let key = (selectedAccount == .rothIRA) ? "Roth IRA" : "Brokerage"
        let candidates = [
            "\(BackendConfig.baseURLString)/api/budget/\(username)/monthly",
            "\(BackendConfig.baseURLString)/api/budget/\(username.lowercased())/monthly"
        ]

        for urlStr in candidates {
            guard let url = URL(string: urlStr) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else { continue }

                struct BudgetResponse: Decodable { let budget: [String: Double] }

                if let decoded = try? JSONDecoder().decode(BudgetResponse.self, from: data),
                   let val = decoded.budget[key], val > 0 {
                    monthlyContribution = val
                    return true
                }
                if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let val = map[key] as? Double, val > 0 {
                        monthlyContribution = val
                        return true
                    }
                    if let budgetMap = map["budget"] as? [String: Any],
                       let valAny = budgetMap[key],
                       let val = (valAny as? Double) ?? Double("\(valAny)") {
                        if val > 0 {
                            monthlyContribution = val
                            return true
                        }
                    }
                }
            } catch {
                continue
            }
        }

        budgetMissingMessage = "Please add a monthly amount for “\(key)” in your Budget first."
        showBudgetMissingAlert = true
        return false
    }

    func generatePortfolioFromLLM() async {
        let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/portfolio")!
        let payload: [String: String] = [
            "username": username,
            "goals": goals,
            "riskTolerance": riskTolerance,
            "experience": investingExperience,
            "age": age,
            "timeHorizon": timeHorizon,
            "taxPriority": taxPriority,
            "withdrawalFlexibility": withdrawalFlexibility,
            "account": selectedAccount.apiValue,
            "monthlyContribution": String(monthlyContribution)
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
        let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/save-original")!
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
