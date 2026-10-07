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


    var body: some View {
        List(articles, id: \.title) { article in
            Link(destination: URL(string: article.url)!) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    if let desc = article.description {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }

                    HStack {
                        Spacer()
                        Text("Read more →")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Market News")
        .overlay {
            if articles.isEmpty {
                ProgressView("Loading news...")
                    .padding()
            }
        }
        .onAppear {
            fetchRiskAndNews()
        }
    }


    func fetchRiskAndNews() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/portfolio/risk/\(username)") else { return }

        URLSession.shared.dataTask(with: BackendConfig.authenticatedRequest(url: url)) { data, _, _ in
            if let data = data,
               let risk = String(data: data, encoding: .utf8)?.capitalized {
                DispatchQueue.main.async {
                    self.riskTolerance = risk
                    fetchNews(for: risk)
                }
            }
        }.resume()
    }

    // the server fetches the news (its NewsAPI key never ships in the app) and picks the topic from the risk level
    func fetchNews(for risk: String) {
        var components = URLComponents(string: "\(BackendConfig.baseURLString)/api/news")
        components?.queryItems = [URLQueryItem(name: "risk", value: risk.lowercased())]
        guard let url = components?.url else { return }

        URLSession.shared.dataTask(with: BackendConfig.authenticatedRequest(url: url)) { data, response, error in
            guard !AppBanner.reportIfFailed("load market news", data, response, error),
                  let data = data,
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
