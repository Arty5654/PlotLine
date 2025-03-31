//
//  IdentifiableString.swift
//  PlotLine
//
//  Created by Alex Younkers on 3/27/25.
//

import Foundation

extension String: Identifiable {
    public var id: String { self }
}

