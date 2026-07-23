//
//  ModelProvider.swift
//  MyAIAgent
//

import Foundation

/// Events the agent engine consumes — provider-neutral, so the engine is
/// testable with a fake and a different backend could plug in behind the
/// same seam.
nonisolated enum StreamEvent: Equatable, Sendable {
    case textStarted
    case textDelta(String)
    case toolUseStarted(id: String, name: String)
    case toolInputDelta(id: String, partialJSON: String)
    case toolUseFinished(id: String)
    case finished(stopReason: StopReason)

    nonisolated enum StopReason: Equatable, Sendable {
        case endTurn
        case toolUse
        case maxTokens
        case other(String)
    }
}

/// The network boundary seam. `ClaudeProvider` is the production
/// implementation; tests use `FakeModelProvider` with scripted events.
nonisolated protocol ModelProvider: Sendable {
    func stream(
        system: String,
        tools: [ToolDefinition],
        messages: [WireMessage]
    ) -> AsyncThrowingStream<StreamEvent, any Error>
}
