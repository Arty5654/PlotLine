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
    
    // For watchlists
    @State private var watchlist: [String] = []
    @State private var newSymbol: String = ""


    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

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
                    
                    // Read only
                    PieChartView(assets: .constant(portfolio.parsedAssets.map {
                        EditableAsset(name: $0.name, percentage: $0.percentage, amount: $0.amount)
                    }), editable: false, selectedAssetID: .constant(nil))
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

                    Text("Total: \(portfolio.totalMonthlyAmountDouble, specifier: "%.2f")")
                        .bold()
                        .padding(.top, 5)

                    NavigationLink(destination: PortfolioExplanationView(portfolioText: portfolio.portfolio)) {
                        Text("Why These Investments?")
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    
                    if let portfolio = savedPortfolio {
                        HStack {
                            NavigationLink(destination:
                            EditPortfolioView(
                                assets: portfolio.parsedAssets.map {
                                    EditableAsset(name: $0.name, percentage: $0.percentage, amount: $0.amount)
                                },
                                investmentFrequency: portfolio.investmentFrequency,
                                totalAmount: Double(portfolio.totalMonthlyAmountDouble)
                            )
                            ) {
                                Text("Edit Portfolio")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }

                            Button("Revert to LLM Portfolio") {
                                revertToLLMGeneratedPortfolio()
                            }
                            .foregroundColor(.red)
                            .padding()
                        }
                        Text("Disclaimer: The information provided is NOT financial advice. We are not financial advisers, accountants or the like.")
                            .font(.system(size: 10))
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
        print("Fetching portfolio for: \(username)")
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
    
    func revertToLLMGeneratedPortfolio() {
        guard let url = URL(string: "http://localhost:8080/api/llm/portfolio/revert/\(username)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        URLSession.shared.dataTask(with: request) { _, _, _ in
            fetchSavedPortfolio()
        }.resume()
    }
}

struct PieChartView: View {
    @Binding var assets: [EditableAsset]
    var editable: Bool = false
    @Binding var selectedAssetID: UUID?

    var body: some View {
        Chart {
            ForEach(assets) { asset in
                SectorMark(
                    angle: .value("Allocation", asset.percentage),
                    innerRadius: .ratio(0.5),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Asset", asset.name))
                .opacity(selectedAssetID == asset.id ? 1.0 : 0.6)
                .annotation(position: .overlay) {
                    Text(asset.name)
                        .font(.caption)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture()
                            .onEnded { value in
                                // Optional: add logic to detect tapped sector
                                print("Pie chart tapped – add logic if needed.")
                            }
                    )
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
        return "Monthly"
    }

//    var totalMonthlyAmount: String {
//        let pattern = #"(?i)\*\*Total Investment per Month:\*\*\s*\$([\d,]+\.\d{2})"#
//        if let regex = try? NSRegularExpression(pattern: pattern),
//           let match = regex.firstMatch(in: portfolio, range: NSRange(portfolio.startIndex..., in: portfolio)),
//           let range = Range(match.range(at: 1), in: portfolio) {
//            return "$" + String(portfolio[range])
//        }
//        return "Amount not found"
//    }
    
    var totalMonthlyAmountDouble: Double {
        return parsedAssets.reduce(0.0) { $0 + $1.amount }
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
