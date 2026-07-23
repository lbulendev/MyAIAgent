//
//  SmokeTests.swift
//  MyAIAgentTests
//

import Foundation
import Testing
@testable import MyAIAgent

// Critical path only: a lead opens, the agent streams a reply, and a tool
// round-trip completes. If anything here fails, stop and fix before reading
// other results.
@Suite("Smoke", .tags(.smoke))
struct SmokeTests {

    @Suite("Agent run", .tags(.agent))
    @MainActor
    struct AgentRun {
        @Test("A streamed reply lands in the transcript and the agent goes idle")
        func streamsReply() async throws {
            let provider = FakeModelProvider(script: [.textTurn("Happy to help with that tune-up!")])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.startIfNeeded()
            try await waitUntil { engine.state == .idle && !engine.transcript.isEmpty }

            #expect(engine.transcript.map(\.kind) == [.customer, .agent])
            #expect(engine.transcript.last?.text == "Happy to help with that tune-up!")
        }

        @Test("A tool call round-trips: results go back and the next turn streams")
        func toolRoundTrip() async throws {
            let provider = FakeModelProvider(script: [
                .toolTurn(id: "tu_1", name: "lookup_customer", inputJSON: #"{"name": "Dana Reyes"}"#),
                .textTurn("Found you, Dana — Thursday works."),
            ])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.startIfNeeded()
            try await waitUntil { engine.state == .idle && engine.transcript.count == 3 }

            // Second request must carry the tool result in a single user message.
            #expect(provider.recordedRequests.count == 2)
            let lastMessage = try #require(provider.recordedRequests[1].last)
            #expect(lastMessage.role == "user")
            #expect(lastMessage.content.contains { block in
                if case .toolResult(let toolUseID, _, false) = block { return toolUseID == "tu_1" }
                return false
            })
            // The transcript narrates the tool activity between the turns.
            #expect(engine.transcript.map(\.kind) == [.customer, .toolActivity, .agent])
        }
    }
}
