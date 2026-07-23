//
//  TestSupport.swift
//  MyAIAgentTests
//

import Foundation
import Synchronization
@testable import MyAIAgent

/// Scripted stand-in at the network boundary. Each `stream()` call consumes
/// the next scripted turn and records the request, so tests can assert on
/// the exact wire conversation the engine sent.
nonisolated final class FakeModelProvider: ModelProvider {
    enum ScriptedTurn {
        case events([StreamEvent])
        case failure(any Error)
        /// A stream that never produces or finishes — for cancellation tests.
        case hang
    }

    private struct State {
        var script: [ScriptedTurn]
        var requests: [[WireMessage]] = []
    }

    private let state: Mutex<State>

    init(script: [ScriptedTurn]) {
        state = Mutex(State(script: script))
    }

    var recordedRequests: [[WireMessage]] {
        state.withLock { $0.requests }
    }

    func stream(
        system: String,
        tools: [ToolDefinition],
        messages: [WireMessage]
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        let turn: ScriptedTurn? = state.withLock { state in
            state.requests.append(messages)
            return state.script.isEmpty ? nil : state.script.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            switch turn {
            case .events(let events):
                for event in events { continuation.yield(event) }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            case .hang:
                break  // never yields; consumer cancellation terminates it
            case nil:
                continuation.finish(throwing: AgentError.generic)
            }
        }
    }
}

extension FakeModelProvider.ScriptedTurn {
    /// A plain streamed text reply ending the turn.
    static func textTurn(_ text: String) -> Self {
        .events([.textStarted, .textDelta(text), .finished(stopReason: .endTurn)])
    }

    /// A turn where the model calls one tool with the given JSON input.
    static func toolTurn(id: String, name: String, inputJSON: String) -> Self {
        .events([
            .toolUseStarted(id: id, name: name),
            .toolInputDelta(id: id, partialJSON: inputJSON),
            .toolUseFinished(id: id),
            .finished(stopReason: .toolUse),
        ])
    }
}

// MARK: Engine factory

@MainActor
func makeEngine(
    lead: Lead = .sample,
    provider: FakeModelProvider,
    store: CRMStore? = nil
) -> (engine: AgentEngine, store: CRMStore, outbox: AgentOutbox) {
    let store = store ?? CRMStore(leads: [lead])
    let outbox = AgentOutbox(directory: temporaryOutboxDirectory())
    let engine = AgentEngine(lead: lead, provider: provider, store: store, outbox: outbox)
    return (engine, store, outbox)
}

/// Isolated per-test storage so persistence tests never interfere.
nonisolated func temporaryOutboxDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("outbox-tests-\(UUID().uuidString)", isDirectory: true)
}

/// Polls until the condition holds or the deadline passes — the fake
/// provider is synchronous, so runs settle within a few ticks.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw AgentError.generic  // timeout — the awaited state never arrived
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
