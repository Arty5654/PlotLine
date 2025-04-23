//
//  ReactionBubble.swift
//  PlotLine
//
//  Created by Alex Younkers on 4/23/25.
//


import SwiftUI

struct ReactionBubble: View {
    @EnvironmentObject private var vm: ChatViewModel
    let message: ChatMessage
    let emoji: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
            Text("\(count)")
                .font(.caption2)
        }
        .padding(6)
        .background(Color.blue.opacity(0.2))   // ← was systemGray5
        .cornerRadius(8)
        .onTapGesture {
            Task { await vm.removeReaction(to: message, emoji: emoji) }
        }
    }
}

struct ReactionBubbles: View {
    let message: ChatMessage
    @EnvironmentObject private var vm: ChatViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Sort the keys for stable order
            ForEach(message.reactions.keys.sorted(), id: \.self) { emoji in
                ReactionBubble(
                    message: message,
                    emoji: emoji,
                    count: message.reactions[emoji]!
                )
                .environmentObject(vm) // or pass env-object later
            }
        }
    }
}
