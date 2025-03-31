//
//  WatchlistView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/31/25.
//

import SwiftUI

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

            List {
                ForEach(watchlist, id: \.self) { symbol in
                    HStack {
                        Text(symbol)
                        Spacer()
                        Button("Remove") {
                            removeSymbolFromWatchlist(symbol)
                        }
                        .foregroundColor(.red)
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


#Preview {
    WatchlistView()
}
