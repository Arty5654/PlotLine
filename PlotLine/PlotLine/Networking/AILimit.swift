//
//  AILimit.swift
//  PlotLine
//
//  AI features (receipt scan, food photo, AI budget and portfolio, grocery generation) are capped
//  per user per day. Over the cap the server answers 429 with a "try again in N hours" message.
//

import Foundation

struct AILimitError: LocalizedError {
    let message: String

    var errorDescription: String? { message }

    /// The server's message if this response is the daily AI limit, nil otherwise.
    static func from(_ data: Data?, _ response: URLResponse?) -> AILimitError? {
        guard let http = response as? HTTPURLResponse, http.statusCode == 429 else { return nil }
        struct Body: Decodable { let error: String? }
        let message = data.flatMap { try? JSONDecoder().decode(Body.self, from: $0) }?.error
        return AILimitError(message: message ?? "You've reached today's limit for AI features. Try again tomorrow.")
    }
}
