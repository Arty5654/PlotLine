//
//  ProfileRequest.swift
//  PlotLine
//
//  Created by Alex Younkers on 2/20/25.
//

struct UserProfile: Codable {
    let username: String
    let name: String?
    let birthday: String?
    let phone: String
    let city: String?
    let profileUrl: String?
}
