//
//  EmojiPickerView.swift
//  PlotLine
//
//  Created by Alex Younkers on 4/23/25.
//

import SwiftUI

struct EmojiPickerView: View {
    let emojis: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack {
            Text("Pick an emoji").font(.headline).padding()
            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 20) {
                ForEach(emojis, id: \.self) { emoji in
                    Button(emoji) {
                        onSelect(emoji)
                    }
                    .font(.largeTitle)
                }
            }
            .padding()
            Spacer()
        }
    }
}
