// ChatViewModel.swift

import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""

    private let api = ChatAPI()
    var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }

    func load() async {
        do { messages = try await api.fetchFeed(userId: username) }
        catch { print("Fetch feed error:", error) }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        do {
            try await api.postMessage(userId: username, content: text)
            draft = ""
            await load()
        } catch {
            print("Send message error:", error)
        }
    }

    // new: add a reaction then reload
    func react(to msg: ChatMessage, emoji: String) async {
        do {
            try await api.addReaction(owner: msg.creator, messageId: msg.id, emoji: emoji)
            await load()
        } catch {
            print("Reaction error:", error)
        }
    }

    // new: add a reply then reload
    func reply(to msg: ChatMessage, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await api.addReply(owner: msg.creator, messageId: msg.id, text: trimmed)
            await load()
        } catch {
            print("Reply error:", error)
        }
    }
    
    func removeReaction(to msg: ChatMessage, emoji: String) async {
        do {
            try await api.removeReaction(owner: msg.creator, messageId: msg.id, emoji: emoji)
            await load()
        } catch {
            print("Remove reaction error:", error)
        }
    }
}
