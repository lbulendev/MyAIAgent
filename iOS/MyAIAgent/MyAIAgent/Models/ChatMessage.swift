//
//  ChatMessage.swift
//  MyAIAgent
//

import Foundation

/// One entry in the on-screen transcript. Separate from the wire-format
/// conversation the agent sends to the model — this is what the user sees.
nonisolated struct ChatMessage: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        /// Text from the customer (the lead's message or a follow-up typed in the app).
        case customer
        /// Text from the AI worker, streamed token by token.
        case agent
        /// A note about a tool the agent ran ("Booked appointment #A-1042").
        case toolActivity
        /// A deterministic local reply while offline (guide lookup). Clearly
        /// labeled in the UI — never presented as the AI worker, and never
        /// written into the wire conversation as an assistant message.
        case offlineHelp
    }

    let id: UUID
    var kind: Kind
    var text: String

    init(id: UUID = UUID(), kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}
