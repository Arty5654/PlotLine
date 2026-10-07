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
        catch { AppBanner.report("load messages", error, retry: { [weak self] in Task { await self?.load() } }) }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        do {
            try await api.postMessage(userId: username, content: text)
            draft = ""
            await load()
        } catch {
            AppBanner.report("send your message", error) // the message stays in the box
        }
    }

    // new: add a reaction then reload
    func react(to msg: ChatMessage, emoji: String) async {
        do {
            try await api.addReaction(owner: msg.creator, messageId: msg.id, emoji: emoji)
            await load()
        } catch {
            AppBanner.report("add your reaction", error)
        }
    }

    // new: add a reply then reload; false if it didn't send (the reply box keeps the text)
    @discardableResult
    func reply(to msg: ChatMessage, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        do {
            try await api.addReply(owner: msg.creator, messageId: msg.id, text: trimmed)
            await load()
            return true
        } catch {
            AppBanner.report("send your reply", error)
            return false
        }
    }
    
    func removeReaction(to msg: ChatMessage, emoji: String) async {
        do {
            try await api.removeReaction(owner: msg.creator, messageId: msg.id, emoji: emoji)
            await load()
        } catch {
            AppBanner.report("remove your reaction", error)
        }
    }

    // Tapping an existing reaction bubble: try to remove (user un-reacts),
    // fall back to adding if the server says they hadn't reacted yet.
    func toggleReaction(to msg: ChatMessage, emoji: String) async {
        do {
            try await api.removeReaction(owner: msg.creator, messageId: msg.id, emoji: emoji)
        } catch {
            do {
                try await api.addReaction(owner: msg.creator, messageId: msg.id, emoji: emoji)
            } catch {
                AppBanner.report("update your reaction", error)
            }
        }
        await load()
    }
}
