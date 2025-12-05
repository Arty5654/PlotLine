//
//  WatchlistView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/31/25.
//

import SwiftUI
import Charts

struct FMPSearchResult: Decodable, Identifiable {
    var id: String { symbol + (exchange ?? "") }
    let symbol: String
    let name: String?
    let exchange: String?
    let currency: String?

    private enum CodingKeys: String, CodingKey {
        case symbol, name, currency
        case exchangeShortName
        case stockExchange
        case exchange // sometimes present in some endpoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol   = try c.decode(String.self, forKey: .symbol)
        name     = try? c.decode(String.self, forKey: .name)
        currency = try? c.decode(String.self, forKey: .currency)

        // prefer short name (e.g. "NASDAQ", "NYSE"), else fall back
        let short = try? c.decode(String.self, forKey: .exchangeShortName)
        let stock = try? c.decode(String.self, forKey: .stockExchange)
        let raw   = try? c.decode(String.self, forKey: .exchange)
        exchange  = short ?? stock ?? raw
    }
}


// MARK: - Tiny debouncer to avoid spamming API while typing
final class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?

    init(delay: TimeInterval) { self.delay = delay }

    func run(_ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

struct WatchlistView: View {
    @State private var watchlist: [String] = []
    @State private var newSymbol: String = ""

    // live search
    @State private var suggestions: [FMPSearchResult] = []
    @State private var isSearching = false
    private let debouncer = Debouncer(delay: 0.25)

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Your Watchlist")
                .font(.largeTitle)
                .bold()

            // Input row
            HStack {
                TextField("Add symbol", text: $newSymbol)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .onChange(of: newSymbol) { q in
                        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            suggestions = []
                            isSearching = false
                            return
                        }
                        isSearching = true
                        debouncer.run { searchSymbols(query: trimmed) { results in
                            DispatchQueue.main.async {
                                // Optional: cap results and de-dup by symbol
                                let unique = Dictionary(grouping: results, by: { $0.symbol })
                                    .values
                                    .compactMap { $0.first }
                                self.suggestions = Array(unique.prefix(8))
                                self.isSearching = false
                            }
                        }}
                    }
                    .onSubmit {
                        addSymbolToWatchlist()
                    }

                Button("Add") {
                    addSymbolToWatchlist()
                }
                .disabled(newSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)

            // Suggestions dropdown
            if isSearching {
                ProgressView().padding(.horizontal)
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions) { item in
                        Button {
                            // auto-add on tap
                            newSymbol = item.symbol
                            suggestions = []
                            addSymbolToWatchlist()
                        } label: {
                            HStack(spacing: 8) {
                                Text(item.symbol).bold()
                                Text(item.name ?? "")
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.exchange ?? "")
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }

            // Watchlist
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(watchlist, id: \.self) { symbol in
                        VStack(alignment: .leading, spacing: 10) {
                            StockGraphView(symbol: symbol)
                            Button("Remove \(symbol)") {
                                removeSymbolFromWatchlist(symbol)
                            }
                            .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding()
        .onTapGesture {
            // Dismiss suggestions when tapping outside
            suggestions = []
        }
        .onAppear {
            fetchWatchlist()
        }
    }

    // MARK: - Networking: watchlist CRUD
    func fetchWatchlist() {
        guard let url = URL(string: "http://localhost:8080/api/watchlist/\(username)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                DispatchQueue.main.async {
                    self.watchlist = decoded
                }
            }
        }.resume()
    }

    func addSymbolToWatchlist() {
        let symbol = newSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty,
              let url = URL(string: "http://localhost:8080/api/watchlist/add")
        else { return }

        let payload = ["username": username, "symbol": symbol]
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            fetchWatchlist()
            DispatchQueue.main.async {
                newSymbol = ""
                suggestions = []
            }
        }.resume()
    }

    func removeSymbolFromWatchlist(_ symbol: String) {
        guard let url = URL(string: "http://localhost:8080/api/watchlist/remove") else { return }

        let payload = ["username": username, "symbol": symbol]
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            fetchWatchlist()
        }.resume()
    }

    private func searchSymbols(query: String, completion: @escaping ([FMPSearchResult]) -> Void) {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "StockKey") as? String,
              let url = URL(string:
                "https://financialmodelingprep.com/stable/search-name?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&limit=50&apikey=\(apiKey)"
              ) else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                print("Search HTTP \(http.statusCode)")
                if let data, let body = String(data: data, encoding: .utf8) { print(body) }
                completion([])
                return
            }
            guard let data = data,
                  let results = try? JSONDecoder().decode([FMPSearchResult].self, from: data) else {
                completion([])
                return
            }

            let allowed = Set(["NYSE","NASDAQ"])
            // keep only NYSE/NASDAQ
            let filtered = results.filter { r in
                guard let ex = r.exchange?.uppercased() else { return false }
                return allowed.contains(ex)
            }

            // de-dupe by symbol and cap
            let unique = Dictionary(grouping: filtered, by: { $0.symbol })
                .values.compactMap { $0.first }
            completion(Array(unique.prefix(20)))
        }.resume()
    }

}

// MARK: - Stock chart using FMP
struct StockGraphView: View {
    let symbol: String
    @State private var selectedRange: String = "1D"
    @State private var prices: [ChartData] = []
    @State private var refreshTimer: Timer?

    // Keep using your existing Info.plist key
    private var apiKey: String {
        return Bundle.main.object(forInfoDictionaryKey: "StockKey") as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(symbol.uppercased()) — $\(String(format: "%.2f", prices.last?.price ?? 0))")
                .font(.title2)
                .bold()

            Picker("Range", selection: $selectedRange) {
                Text("1D").tag("1D")
                Text("1W").tag("1W")
                Text("1M").tag("1M")
                Text("1Y").tag("1Y")
                Text("5Y").tag("5Y")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom, 4)

            if prices.isEmpty {
                ProgressView("Loading...")
                    .onAppear {
                        fetchPrices()
                        startAutoRefresh()
                    }
            } else {
                Chart(prices) {
                    LineMark(x: .value("Date", $0.date), y: .value("Price", $0.price))
                }
                .frame(height: 200)
            }
        }
        .onDisappear { stopAutoRefresh() }
        .onChange(of: selectedRange) { _ in
            fetchPrices()
            if selectedRange == "1D" { startAutoRefresh() } else { stopAutoRefresh() }
        }
    }

    // MARK: - Auto refresh (intraday only)
    func startAutoRefresh() {
        stopAutoRefresh()
        guard selectedRange == "1D" else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 65, repeats: true) { _ in
            fetchPrices()
        }
    }
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Fetch with FMP (using /stable endpoints)
    // MARK: - Fetch with FMP (Stock Chart Light API)
    func fetchPrices() {
        guard !apiKey.isEmpty else {
            print("Missing FMP API key in Info.plist (StockKey).")
            return
        }

        // How many calendar days back to ask from /light
        let daysBack: Int
        switch selectedRange {
        case "1D": daysBack = 5      // show last ~5 EOD points (light has only daily)
        case "1W": daysBack = 10
        case "1M": daysBack = 45
        case "1Y": daysBack = 420
        case "5Y": daysBack = 5 * 365
        default:   daysBack = 90
        }

        guard let url = lightURL(daysBack: daysBack) else { return }

        var req = URLRequest(url: url)
        req.setValue("PlotLine/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse else { return }
            guard http.statusCode == 200, let data = data else {
                print("HTTP error: \(http.statusCode)")
                return
            }

            do {
                let rows = try JSONDecoder().decode([FMPLightRow].self, from: data)
                var daily = rows.compactMap { row -> ChartData? in
                    guard let d = FMPDate.isoDateOnly(row.date) else { return nil }
                    return ChartData(date: d, price: row.price)
                }
                .sorted { $0.date < $1.date }

                if selectedRange == "1Y" || selectedRange == "5Y" {
                    daily = downsampleWeekly(daily)
                }

                DispatchQueue.main.async {
                    self.prices = daily
                }
            } catch {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("FMP parse error: \(error.localizedDescription)\n\(body)")
            }
        }.resume()
    }
    
    private func lightURL(daysBack: Int) -> URL? {
        let to = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -daysBack, to: to) else { return nil }

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"

        let fromStr = df.string(from: from)
        let toStr   = df.string(from: to)

        let s = symbol.uppercased()
        let urlStr = "https://financialmodelingprep.com/stable/historical-price-eod/light?symbol=\(s)&from=\(fromStr)&to=\(toStr)&apikey=\(apiKey)"
        return URL(string: urlStr)
    }


    // Very simple weekly sampler: keep one point per ISO week (latest that week)
    private func downsampleWeekly(_ data: [ChartData]) -> [ChartData] {
        var byWeek: [String: ChartData] = [:]
        let cal = Calendar(identifier: .iso8601)
        for point in data {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: point.date)
            let key = "\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
            if let existing = byWeek[key] {
                if point.date > existing.date { byWeek[key] = point }
            } else {
                byWeek[key] = point
            }
        }
        return byWeek.values.sorted(by: { $0.date < $1.date })
    }
}

// MARK: - FMP DTOs + date helpers
private struct FMPIntradayBar: Decodable {
    let date: String        // "2025-12-04 15:55:00"
    let close: Double
}

private struct FMPHistoricalEnvelope: Decodable {
    let symbol: String?
    let historical: [FMPDailyRow]
}
private struct FMPDailyRow: Decodable {
    let date: String        // "2025-12-03"
    let close: Double
}
private struct FMPLightRow: Decodable {
    let symbol: String?
    let date: String      // "yyyy-MM-dd"
    let price: Double
    let volume: Int64?
}



private enum FMPDate {
    static func isoDateTime(_ s: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0) // treat as UTC for chart spacing
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: s)
    }
    static func isoDateOnly(_ s: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }
}

// MARK: - Chart data
struct ChartData: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
}

extension DateFormatter {
    static let dateOnly: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

#Preview {
    WatchlistView()
}
