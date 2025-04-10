//
//  WatchlistView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/31/25.
//

import SwiftUI
import Charts

struct WatchlistView: View {
    @State private var watchlist: [String] = []
    @State private var newSymbol: String = ""

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Your Watchlist")
                .font(.largeTitle)
                .bold()

            HStack {
                TextField("Add symbol", text: $newSymbol)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    addSymbolToWatchlist()
                }
                .disabled(newSymbol.isEmpty)
            }
            .padding(.horizontal)

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
        .onAppear {
            fetchWatchlist()
        }
    }

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
        guard let url = URL(string: "http://localhost:8080/api/watchlist/add") else { return }

        let payload = ["username": username, "symbol": newSymbol]
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, _, _ in
            fetchWatchlist()
            newSymbol = ""
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
}

struct StockGraphView: View {
    let symbol: String
    @State private var selectedRange: String = "1D"
    @State private var prices: [ChartData] = []
    @State private var refreshTimer: Timer?
    
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
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: selectedRange) { _ in
            fetchPrices()
        }
    }
    
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
    
    func fetchPrices() {
        let function: String
        switch selectedRange {
        case "1D": function = "TIME_SERIES_INTRADAY&interval=5min"
        case "1W", "1M": function = "TIME_SERIES_DAILY"
        case "1Y", "5Y": function = "TIME_SERIES_WEEKLY"
        default: return
        }
        
        guard let url = URL(string: "https://www.alphavantage.co/query?function=\(function)&symbol=\(symbol)&apikey=\(apiKey)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                print("No data received from Alpha Vantage")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let error = json["Note"] as? String {
                        print("API rate limit reached: \(error)")
                        return
                    }
                    
                    if let timeSeries = json.values.first(where: { $0 is [String: Any] }) as? [String: Any] {
                        let sorted = timeSeries.compactMap { (key, value) -> ChartData? in
                            guard let dict = value as? [String: String],
                                  let close = dict["4. close"],
                                  let price = Double(close),
                                  let date = ISO8601DateFormatter().date(from: key.replacingOccurrences(of: " ", with: "T")) ??
                                    DateFormatter.dateOnly.date(from: key) else { return nil }
                            return ChartData(date: date, price: price)
                        }.sorted(by: { $0.date < $1.date })
                        
                        DispatchQueue.main.async {
                            self.prices = sorted
                            print("Loaded \(sorted.count) price points for \(symbol)")
                        }
                    } else {
                        print("Could not find time series data in API response.")
                        print(json)
                    }
                }
            } catch {
                print("JSON parse error: \(error.localizedDescription)")
            }
        }.resume()
    }
}

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
