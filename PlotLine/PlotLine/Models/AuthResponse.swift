//
//  AuthResponse.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/12/25.
//
import Foundation

struct AuthResponse: Codable {
    let success: Bool
    let token: String?
    let error: String?
}


