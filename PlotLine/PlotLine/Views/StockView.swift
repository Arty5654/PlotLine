//
//  StockView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI
import Charts

struct StockView: View {
    @State private var savedPortfolio: SavedPortfolio? = nil

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Investing Tools")
                    .font(.largeTitle)
                    .bold()

                NavigationLink(destination: InvestmentQuizView()) {
                    Label("Take Investing Quiz", systemImage: "questionmark.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }

                if let portfolio = savedPortfolio {
                    Divider()
                    Text("Your Portfolio Allocation")
                        .font(.headline)

                    PieChartView(assets: portfolio.parsedAssets)
                        .frame(height: 300)

                    Text("Investment Breakdown (\(portfolio.investmentFrequency))")
                        .font(.subheadline)
                        .padding(.top, 10)

                    ForEach(portfolio.parsedAssets) { asset in
                        HStack {
                            Text(asset.name)
                            Spacer()
                            Text("\(asset.percentage, specifier: "%.0f")% - $\(asset.amount, specifier: "%.2f")")
                        }
                        .padding(.horizontal)
                    }

                    Text("Total: \(portfolio.totalMonthlyAmount)")
                        .bold()
                        .padding(.top, 5)

                    NavigationLink(destination: PortfolioExplanationView(portfolioText: portfolio.portfolio)) {
                        Text("Why These Investments?")
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            fetchSavedPortfolio()
        }
    }

    func fetchSavedPortfolio() {
        guard let url = URL(string: "http://localhost:8080/api/llm/portfolio/\(username)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let decoded = try? JSONDecoder().decode(SavedPortfolio.self, from: data) {
                DispatchQueue.main.async {
                    self.savedPortfolio = decoded
                }
            }
        }.resume()
    }
}

struct PieChartView: View {
    let assets: [InvestmentAsset]

    var body: some View {
        Chart {
            ForEach(assets) { asset in
                SectorMark(
                    angle: .value("Allocation", asset.percentage),
                    innerRadius: .ratio(0.5),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Asset", asset.name))
                .annotation(position: .overlay) {
                    Text(asset.name)
                        .font(.caption)
                }
            }
        }
    }
}


struct SavedPortfolio: Codable {
    let username: String
    let portfolio: String
    let riskTolerance: String

    var parsedAssets: [InvestmentAsset] {
        let regex = try? NSRegularExpression(pattern: #"(?<=\*\*)([A-Z]+).+?(\d+)%.*?\$\s?(\d+(\.\d+)?)"#, options: [])
        var results: [InvestmentAsset] = []

        let nsrange = NSRange(portfolio.startIndex..<portfolio.endIndex, in: portfolio)
        regex?.enumerateMatches(in: portfolio, options: [], range: nsrange) { match, _, _ in
            if let match = match,
               let nameRange = Range(match.range(at: 1), in: portfolio),
               let percentRange = Range(match.range(at: 2), in: portfolio),
               let amountRange = Range(match.range(at: 3), in: portfolio) {

                let name = String(portfolio[nameRange])
                let percentage = Double(portfolio[percentRange]) ?? 0
                let amount = Double(portfolio[amountRange]) ?? 0

                results.append(InvestmentAsset(name: name, percentage: percentage, amount: amount))
            }
        }

        return results
    }

    var investmentFrequency: String {
        if let match = portfolio.range(of: #"(?i)Invest.*?(Monthly|Weekly|Annually)"#, options: .regularExpression) {
            return String(portfolio[match])
        }
        return "Frequency not found"
    }

    var totalMonthlyAmount: String {
        if let match = portfolio.range(of: #"\$\d+(,\d{3})*(\.\d+)?/month"#, options: .regularExpression) {
            return String(portfolio[match])
        }
        return "Amount not found"
    }
}


struct InvestmentAsset: Identifiable {
    var id = UUID()
    let name: String
    let percentage: Double
    let amount: Double
}

struct PortfolioExplanationView: View {
    let portfolioText: String

    var body: some View {
        ScrollView {
            Text(portfolioText)
                .padding()
        }
        .navigationTitle("Investment Rationale")
    }
}





#Preview {
    StockView()
}

