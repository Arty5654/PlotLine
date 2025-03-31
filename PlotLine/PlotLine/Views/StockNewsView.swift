//
//  StockNewsView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/31/25.
//

import SwiftUI

struct StockNewsView: View {
    @State private var articles: [NewsArticle] = []
    @State private var riskTolerance: String = "Medium"

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    private var apiKey: String {
        return Bundle.main.object(forInfoDictionaryKey: "NewsAPIKey") as? String ?? "NO KEY FOUND"
    }


    var body: some View {
        VStack(alignment: .leading) {
            Text("Trending News (\(riskTolerance) Risk)")
                .font(.headline)
                .padding(.bottom, 5)

            if articles.isEmpty {
                ProgressView("Loading news...")
            } else {
                ForEach(articles, id: \.title) { article in
                    Link(destination: URL(string: article.url)!) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(article.title).font(.subheadline).bold()
                            Text(article.description ?? "").font(.caption)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            fetchRiskAndNews()
        }
    }

    func fetchRiskAndNews() {
        guard let url = URL(string: "http://localhost:8080/api/llm/portfolio/risk/\(username)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let risk = String(data: data, encoding: .utf8)?.capitalized {
                DispatchQueue.main.async {
                    self.riskTolerance = risk
                    fetchNews(for: risk)
                }
            }
        }.resume()
    }

    func fetchNews(for risk: String) {
        let topic: String
        switch risk.lowercased() {
        case "low": topic = "long term investing"
        case "high": topic = "growth stocks OR speculative tech"
        default: topic = "stock market investing"
        }
        print("TOPIC IN NEWS: " + topic)
        let encoded = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let urlStr = "https://newsapi.org/v2/everything?q=\(encoded)&sortBy=publishedAt&language=en&apiKey=\(apiKey)"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(NewsResponse.self, from: data) else { return }

            DispatchQueue.main.async {
                self.articles = decoded.articles
            }
        }.resume()
    }
}

struct NewsArticle: Decodable {
    let title: String
    let description: String?
    let url: String
}

struct NewsResponse: Decodable {
    let articles: [NewsArticle]
}


#Preview {
    StockNewsView()
}
