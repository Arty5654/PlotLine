//
//  PortfolioRatingView.swift
//  PlotLine
//

import SwiftUI

struct PortfolioRatingView: View {

    enum ViewAccount: String, CaseIterable, Identifiable {
        case brokerage = "Brokerage"
        case rothIRA   = "Roth IRA"
        var id: String { rawValue }
        var apiValue: String { self == .brokerage ? "BROKERAGE" : "ROTH_IRA" }
    }

    struct HoldingEntry: Identifiable {
        let id = UUID()
        var ticker: String = ""
        var percentage: String = ""
    }

    struct PortfolioRating: Decodable {
        let overallScore: Double
        let letter: String
        let summary: String
        let breakdown: Breakdown
        let suggestions: [String]

        struct Breakdown: Decodable {
            let diversification: Category
            let riskBalance: Category
            let growthPotential: Category
            let costEfficiency: Category
            let accountFit: Category
        }

        struct Category: Decodable {
            let score: Double
            let comment: String
        }
    }

    @Environment(\.colorScheme) var colorScheme

    @State private var viewAccount: ViewAccount = .brokerage
    @State private var holdings: [HoldingEntry] = [HoldingEntry()]
    @State private var isLoading = false
    @State private var rating: PortfolioRating? = nil
    @State private var errorText: String? = nil

    private let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"

    private var adaptiveTextColor: Color {
        colorScheme == .dark ? .white : .blue
    }

    private var totalPercentage: Double {
        holdings.compactMap { Double($0.percentage) }.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                Picker("Account", selection: $viewAccount) {
                    ForEach(ViewAccount.allCases) { a in Text(a.rawValue).tag(a) }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewAccount) { _ in
                    rating = nil
                    errorText = nil
                    loadSavedPortfolio()
                }

                // Holdings input card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Current Holdings")
                            .font(.headline)
                        Spacer()
                        Button(action: loadSavedPortfolio) {
                            Label("Load Saved", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundColor(adaptiveTextColor)
                        }
                    }

                    ForEach($holdings) { $holding in
                        HStack(spacing: 8) {
                            TextField("Ticker", text: $holding.ticker)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .frame(maxWidth: 100)
                                .padding(8)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .tint(adaptiveTextColor)

                            TextField("%", text: $holding.percentage)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 70)
                                .padding(8)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .tint(adaptiveTextColor)

                            Text("%")
                                .foregroundColor(.secondary)

                            Spacer()

                            if holdings.count > 1 {
                                Button(role: .destructive) {
                                    holdings.removeAll { $0.id == holding.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }

                    Button {
                        holdings.append(HoldingEntry())
                    } label: {
                        Label("Add Holding", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundColor(adaptiveTextColor)
                    }

                    HStack {
                        Text("Total: \(Int(totalPercentage))%")
                            .font(.caption)
                            .foregroundColor(abs(totalPercentage - 100) < 1 ? .green : .orange)
                        Spacer()
                        if abs(totalPercentage - 100) >= 1 {
                            Text("Should sum to 100%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Rate button
                let canSubmit = !holdings.filter { !$0.ticker.isEmpty }.isEmpty && abs(totalPercentage - 100) < 1
                Button {
                    Task { await ratePortfolio() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "star.fill")
                        }
                        Text(isLoading ? "Analyzing…" : "Rate My Portfolio")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? Color.purple : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(isLoading || !canSubmit)

                if let error = errorText {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                if let rating = rating {
                    RatingCard(rating: rating)
                }

                Text("Disclaimer: This AI-generated rating is NOT financial advice. We are not financial advisers.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("AI Portfolio Rating")
        .onAppear { loadSavedPortfolio() }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }

    private func loadSavedPortfolio() {
        var components = URLComponents(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/\(username)")!
        components.queryItems = [URLQueryItem(name: "account", value: viewAccount.apiValue)]
        guard let url = components.url else { return }

        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let portfolio = try? JSONDecoder().decode(SavedPortfolio.self, from: data) else { return }

            let entries = portfolio.parsedAssets.map { asset -> HoldingEntry in
                var h = HoldingEntry()
                h.ticker = asset.name
                h.percentage = String(Int(asset.percentage))
                return h
            }

            DispatchQueue.main.async {
                if !entries.isEmpty {
                    self.holdings = entries
                }
            }
        }.resume()
    }

    private func ratePortfolio() async {
        let valid = holdings.filter { !$0.ticker.isEmpty }
        guard !valid.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            rating = nil
            errorText = nil
        }

        var portfolioText = "Holdings:\n"
        for h in valid {
            let pct = h.percentage.isEmpty ? "?" : h.percentage
            portfolioText += "- \(h.ticker.uppercased()): \(pct)%\n"
        }

        let body: [String: String] = [
            "username": username,
            "portfolio": portfolioText,
            "accountType": viewAccount.apiValue
        ]

        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/rate"),
              let jsonData = try? JSONEncoder().encode(body) else {
            await MainActor.run { isLoading = false; errorText = "Invalid request." }
            return
        }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let decoded = try? JSONDecoder().decode(PortfolioRating.self, from: data) {
                await MainActor.run { self.rating = decoded; self.isLoading = false }
                return
            }

            // Fallback: unwrap JSON-encoded string then decode
            if let jsonString = try? JSONDecoder().decode(String.self, from: data),
               let inner = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(PortfolioRating.self, from: inner) {
                await MainActor.run { self.rating = decoded; self.isLoading = false }
                return
            }

            await MainActor.run {
                self.isLoading = false
                self.errorText = "Could not parse rating. Please try again."
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorText = "Request failed. Check your connection and try again."
            }
        }
    }
}

// MARK: - Rating Card

private struct RatingCard: View {
    let rating: PortfolioRatingView.PortfolioRating

    private var scoreColor: Color {
        if rating.overallScore >= 8 { return .green }
        if rating.overallScore >= 6 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header: grade + numeric score
            HStack(alignment: .center) {
                VStack(spacing: 2) {
                    Text(rating.letter)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("Grade")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", rating.overallScore))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("out of 10")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(rating.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Category breakdown
            VStack(alignment: .leading, spacing: 14) {
                Text("Breakdown")
                    .font(.headline)

                RatingRow(label: "Diversification",
                          score: rating.breakdown.diversification.score,
                          comment: rating.breakdown.diversification.comment)
                RatingRow(label: "Risk Balance",
                          score: rating.breakdown.riskBalance.score,
                          comment: rating.breakdown.riskBalance.comment)
                RatingRow(label: "Growth Potential",
                          score: rating.breakdown.growthPotential.score,
                          comment: rating.breakdown.growthPotential.comment)
                RatingRow(label: "Cost Efficiency",
                          score: rating.breakdown.costEfficiency.score,
                          comment: rating.breakdown.costEfficiency.comment)
                RatingRow(label: "Account Fit",
                          score: rating.breakdown.accountFit.score,
                          comment: rating.breakdown.accountFit.comment)
            }

            Divider()

            // Suggestions
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggestions")
                    .font(.headline)
                ForEach(rating.suggestions, id: \.self) { suggestion in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .padding(.top, 3)
                        Text(suggestion)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RatingRow: View {
    let label: String
    let score: Double
    let comment: String

    private var color: Color {
        if score >= 8 { return .green }
        if score >= 6 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.0f / 10", score))
                    .font(.subheadline.bold())
                    .foregroundColor(color)
            }
            ProgressView(value: score, total: 10)
                .tint(color)
            Text(comment)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        PortfolioRatingView()
    }
}
