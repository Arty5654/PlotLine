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

struct SmsRequest: Codable {
    let toNumber: String
}

struct VerificationRequest: Codable {
    let phoneNumber: String
    let code: String
    let username: String
}

