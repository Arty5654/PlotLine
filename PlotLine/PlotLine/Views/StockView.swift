//
//  StockView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI



struct StockView: View {
    @State private var savedPortfolio: String? = nil

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
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
                Text("Your Saved Portfolio")
                    .font(.headline)
                    .padding(.top)
                
                ScrollView {
                    Text(portfolio)
                        .font(.body)
                        .padding()
                }
            }
        }
        .padding()
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
                    self.savedPortfolio = decoded.portfolio
                }
            }
        }.resume()
    }
}

struct SavedPortfolio: Codable {
    let username: String
    let portfolio: String
    let riskTolerance: String
}



#Preview {
    StockView()
}

