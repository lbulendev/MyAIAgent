//
//  AgentState.swift
//  MyAIAgent
//

import Foundation

/// The client-side agent state machine. Every phase of a turn is explicit so
/// the UI can narrate what the agent is doing and tests can pin transitions.
nonisolated enum AgentState: Equatable {
    /// No run in flight; ready for input.
    case idle
    /// Request sent; waiting for the first streamed event.
    case thinking
    /// Streaming assistant text into the transcript.
    case streaming
    /// Executing a tool the model called.
    case executingTool(name: String)
    /// The last run failed; `AgentError` carries the user-facing category.
    case failed(AgentError)
}

/// User-facing error categories. Raw error text never reaches the UI —
/// every thrown error maps into one of these (same pattern as HeartChart
/// and TheMovieDBSwift).
nonisolated enum AgentError: Error, Equatable {
    case offline
    case server
    case generic

    /// Collapse any thrown error into a category.
    static func categorize(_ error: any Error) -> AgentError {
        if let agentError = error as? AgentError { return agentError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut:
                return .offline
            default:
                return .generic
            }
        }
        return .generic
    }
}
