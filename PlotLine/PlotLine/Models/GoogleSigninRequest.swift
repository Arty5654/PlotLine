//
//  GoogleSigninRequest.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/18/25.
//
struct GoogleSignInRequest: Codable {
    let idToken: String
    // only sent once the server asks new users to pick one ("Username Required")
    let username: String?
    let email: String
}

