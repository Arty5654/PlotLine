//
//  AuthRequest.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/12/25.
//
import Foundation

struct SignUpRequest: Codable {
    let phone: String
    let username: String
    let password: String
}

struct SignInRequest: Codable {
    let username: String
    let password: String
}

struct TextRequest: Codable {
    let phone: String
    let username: String
}

