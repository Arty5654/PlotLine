//
//  StockView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI
import Charts

struct StockView: View {
    
    enum ViewAccount: String, CaseIterable, Identifiable {
       case brokerage = "Brokerage"
       case rothIRA   = "Roth IRA"
       var id: String { rawValue }
       var apiValue: String { self == .brokerage ? "BROKERAGE" : "ROTH_IRA" }
    }
    
    @State private var viewAccount: ViewAccount = .brokerage
    @State private var savedPortfolio: SavedPortfolio?

    private let isPreview: Bool

    /// a portfolio to show instead of loading one (Xcode previews)
    init(previewPortfolio: SavedPortfolio? = nil) {
        _savedPortfolio = State(initialValue: previewPortfolio)
        isPreview = previewPortfolio != nil
    }
    
    // For watchlists
    @State private var watchlist: [String] = []
    @State private var newSymbol: String = ""
    
    // For Calander and Reminders
    @EnvironmentObject var calendarViewModel: CalendarViewModel
    @EnvironmentObject var friendVM: FriendsViewModel


    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                
            // Account switcher
               Picker("Account", selection: $viewAccount) {
                   ForEach(ViewAccount.allCases) { acct in
                       Text(acct.rawValue).tag(acct)
                   }
               }
               .pickerStyle(.segmented)
               .onChange(of: viewAccount) { _, newVal in
                   // Clear old data when switching accounts to avoid showing stale charts
                   savedPortfolio = nil
                   fetchSavedPortfolio(for: newVal)
               }
                
                if let portfolio = savedPortfolio {
                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Your allocation")
                        // Read only
                        PieChartView(assets: .constant(portfolio.parsedAssets.map {
                            EditableAsset(name: $0.name, percentage: $0.percentage, amount: $0.amount)
                        }), editable: false, selectedAssetID: .constant(nil))
                        .frame(height: 280)
                        .plCard()
                    }

                    VStack(spacing: PLSpacing.sm) {
                        PLSectionHeader(title: "Breakdown · \(portfolio.investmentFrequency)")
                        VStack(spacing: 0) {
                            ForEach(Array(portfolio.parsedAssets.enumerated()), id: \.element.id) { index, asset in
                                if index > 0 { Divider() }
                                HStack {
                                    Text(asset.name).font(.body.weight(.semibold))
                                    Spacer()
                                    Text("\(asset.percentage, specifier: "%.0f")%")
                                        .foregroundColor(PLColor.textSecondary)
                                    Text("$\(asset.amount, specifier: "%.2f")")
                                        .monospacedDigit()
                                        .frame(minWidth: 90, alignment: .trailing)
                                }
                                .padding(.vertical, 10)
                            }
                            Divider()
                            HStack {
                                Text("Total").font(.body.weight(.semibold))
                                Spacer()
                                Text("$\(portfolio.totalMonthlyAmountDouble, specifier: "%.2f")")
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 10)
                        }
                        .plCard()

                        NavigationLink(destination: PortfolioExplanationView(portfolioText: portfolio.portfolio)) {
                            PLRow(icon: "lightbulb.fill", tint: .orange, title: "Why these investments?")
                        }
                        .buttonStyle(.plain)
                        .plCard()
                    }

                    VStack(spacing: PLSpacing.sm) {
                        NavigationLink(destination:
                        EditPortfolioView(
                            assets: portfolio.parsedAssets.map {
                                EditableAsset(name: $0.name, percentage: $0.percentage, amount: $0.amount)
                            },
                            investmentFrequency: portfolio.investmentFrequency,
                            totalAmount: Double(portfolio.totalMonthlyAmountDouble)
                        )
                        ) {
                            Label("Edit Portfolio", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(PrimaryButton())

                        Button("Revert to AI Portfolio") {
                            revertToLLMGeneratedPortfolio(for: viewAccount)
                        }
                        .buttonStyle(OutlineButton(tint: PLColor.danger))
                    }

                    NavigationLink(destination: InvestmentQuizView(onFinish: {
                        fetchSavedPortfolio(for: viewAccount)
                    })
                    .environmentObject(calendarViewModel)
                    ) {
                        Label("Retake Investing Quiz", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(PLColor.tint)
                    }

                    Text("Disclaimer: The information provided is NOT financial advice. We are not financial advisers, accountants or the like.")
                        .font(.caption)
                        .foregroundColor(PLColor.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.pie")
                            .font(.largeTitle)
                            .foregroundColor(PLColor.textSecondary)
                        Text("No portfolio yet")
                            .font(.headline)
                        Text("Answer a few questions and get a suggested portfolio for this account.")
                            .font(.subheadline)
                            .foregroundColor(PLColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PLSpacing.sm)
                    .plCard()

                    NavigationLink(destination: InvestmentQuizView(onFinish: {
                        fetchSavedPortfolio(for: viewAccount)
                    })
                    .environmentObject(calendarViewModel)
                    ) {
                        Label("Take Investing Quiz", systemImage: "questionmark.circle.fill")
                    }
                    .buttonStyle(PrimaryButton(color: PLColor.success))
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.md)
        }
        .onAppear {
            if !isPreview { fetchSavedPortfolio(for: viewAccount) }
        }

    }

    func fetchSavedPortfolio(for account: ViewAccount) {
        // Prefer new endpoint with query param; if missing, clear the view
        var components = URLComponents(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/\(username)")!
        components.queryItems = [URLQueryItem(name: "account", value: account.apiValue)]

        func decodeAndSet(_ data: Data) {
            if let decoded = try? JSONDecoder().decode(SavedPortfolio.self, from: data) {
                DispatchQueue.main.async {
                    self.savedPortfolio = decoded
                }
            } else {
                DispatchQueue.main.async { self.savedPortfolio = nil }
            }
        }

        guard let url = components.url else { return }

        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data {
                decodeAndSet(data)
            } else {
                // No data for this account; clear the view
                DispatchQueue.main.async { self.savedPortfolio = nil }
            }
        }.resume()
    }

    func revertToLLMGeneratedPortfolio(for account: ViewAccount) {
        var components = URLComponents(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/revert/\(username)")!
        components.queryItems = [URLQueryItem(name: "account", value: account.apiValue)]
        guard let url = components.url else { return }

        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"

        URLSession.shared.dataTask(with: req) { _, _, _ in
            fetchSavedPortfolio(for: account)
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
                                //print("Pie chart tapped – add logic if needed.")
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
        let patterns = [
            #"\*\*([A-Z]+)\s*-\s*(\d+)%%\*\*.*?Allocation:\*\*\s*\$([\d.]+)"#, // Quiz format (double %%)
            #"\*\*([A-Z]+)\*\*\s*-\s*(\d+)%\s*-\s*\$([\d.]+)"#               // Edited format
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            
            var results: [InvestmentAsset] = []
            let nsrange = NSRange(portfolio.startIndex..<portfolio.endIndex, in: portfolio)

            regex.enumerateMatches(in: portfolio, options: [], range: nsrange) { match, _, _ in
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

            if !results.isEmpty {
                return results // Use the first successful pattern
            }
        }

        return []
    }



    var investmentFrequency: String {
        let pattern = #"(?i)\b(Monthly|Weekly|Annually)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: portfolio, range: NSRange(portfolio.startIndex..., in: portfolio)),
           let range = Range(match.range(at: 1), in: portfolio) {
            return portfolio[range].capitalized
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
            VStack(alignment: .leading, spacing: 20) {
                ForEach(splitPortfolioText(), id: \.self) { section in
                    // If we can extract asset details, use a custom layout
                    if let asset = extractAssetInfo(from: section) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("•")
                                Text(asset.name)
                                    .bold()
                                Text("– \(Int(asset.percent))%")
                            }
                            .font(.headline)
                            
                            Text("Allocation: $\(String(format: "%.2f", asset.allocation))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            if let reason = extractReason(from: section) {
                                if let attributed = try? AttributedString(markdown: "**Reason:** \(reason)") {
                                    Text(attributed)
                                } else {
                                    Text("Reason: \(reason)")
                                }
                            }
                        }
                    } else {
                        // Otherwise try to render the section as Markdown
                        if let attributed = try? AttributedString(markdown: section) {
                            Text(attributed)
                        } else {
                            Text(section)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Why These Investments?")
    }
    
    // Replace literal "\n" with actual newline characters, collapse double percent signs, and split on double newline.
    private func splitPortfolioText() -> [String] {
        let replaced = portfolioText
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "%%", with: "%")
        return replaced
            .components(separatedBy: "\n\n")
            .map { formatSummarySection($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // Ensure common summary fields show on new lines for readability.
    private func formatSummarySection(_ text: String) -> String {
        let keys = ["Frequency:", "Total allocation", "Total percent", "Total monthly", "Total amount"]
        var result = text
        for key in keys {
            result = result.replacingOccurrences(of: " " + key, with: "\n" + key)
        }
        // Drop the "Total allocation" line because it's redundant with amount to invest
        let filtered = result
            .components(separatedBy: "\n")
            .filter { !($0.lowercased().contains("total allocation")) }
        return filtered.joined(separator: "\n")
    }
    
    private func extractAssetInfo(from block: String) -> (name: String, percent: Double, allocation: Double)? {
        // The regex looks for a pattern like:
        // **<TICKER> - <PERCENT>%**
        // followed by something like "- **Allocation:** $<ALLOCATION>"
        let pattern = #"\*\*([A-Z]+)\s*-\s*(\d+)%+\*\*\s*-?\s*\*\*Allocation:\*\*\s*\$(\d+(?:\.\d+)?)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        
        let nsRange = NSRange(block.startIndex..<block.endIndex, in: block)
        if let match = regex.firstMatch(in: block, options: [], range: nsRange),
           let nameRange = Range(match.range(at: 1), in: block),
           let percentRange = Range(match.range(at: 2), in: block),
           let allocationRange = Range(match.range(at: 3), in: block) {
            let name = String(block[nameRange])
            let percent = Double(block[percentRange]) ?? 0.0
            let allocation = Double(block[allocationRange]) ?? 0.0
            return (name: name, percent: percent, allocation: allocation)
        }
        return nil
    }
    
    // Extracts the "Reason:" text if available.
    private func extractReason(from block: String) -> String? {
        // Look for a line that starts with "- **Reason:**"
        if let range = block.range(of: "- **Reason:**") {
            // Get substring after "- **Reason:**" and trim it
            let reasonSubstring = block[range.upperBound...]
            return reasonSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}


#Preview {
    StockView()
}
