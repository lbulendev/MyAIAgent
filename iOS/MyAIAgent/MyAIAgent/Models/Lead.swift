//
//  Lead.swift
//  MyAIAgent
//

import Foundation

/// An inbound customer inquiry the AI worker can handle.
nonisolated struct Lead: Identifiable, Hashable, Codable {
    enum Status: String, Codable {
        case new
        case inProgress
        case handled
    }

    let id: UUID
    var customerName: String
    var channel: String
    var message: String
    var status: Status

    init(id: UUID = UUID(), customerName: String, channel: String, message: String, status: Status = .new) {
        self.id = id
        self.customerName = customerName
        self.channel = channel
        self.message = message
        self.status = status
    }
}

// Explicitly nonisolated: the project defaults to MainActor isolation, and
// sample data must stay reachable from nonisolated tests and parsers.
nonisolated extension Lead {
    static let sample = Lead(
        customerName: "Dana Reyes",
        channel: "SMS",
        message: "Hi — my rear derailleur is skipping gears. Can I get a tune-up this week?"
    )

    static let samples: [Lead] = [
        .sample,
        Lead(
            customerName: "Marcus Webb",
            channel: "Web form",
            message: "Do you sell kids' helmets? Looking for something for a 7-year-old."
        ),
        Lead(
            customerName: "Priya Natarajan",
            channel: "SMS",
            message: "Flat tire on my commuter bike. How soon could you fit me in for a repair?"
        ),
    ]
}
