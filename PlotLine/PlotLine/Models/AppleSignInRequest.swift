//
//  AppleSignInRequest.swift
//  PlotLine
//
struct AppleSignInRequest: Codable {
    let identityToken: String
    let rawNonce: String
    // only sent once the server asks for it
    let username: String?
    let linkPassword: String?
}
