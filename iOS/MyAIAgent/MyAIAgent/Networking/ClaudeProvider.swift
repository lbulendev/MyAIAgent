//
//  ClaudeProvider.swift
//  MyAIAgent
//

import Foundation

/// Streams the Anthropic Messages API over SSE and maps wire payloads to
/// provider-neutral `StreamEvent`s. The API key arrives via
/// Secrets.xcconfig -> Info.plist -> Bundle; it is never hardcoded.
nonisolated struct ClaudeProvider: ModelProvider {
    static let model = "claude-opus-4-8"
    static let maxTokens = 4096  // short conversational turns; keeps demo cost bounded

    let apiKey: String

    /// Reads the key the build injected. Nil when Secrets.xcconfig is
    /// missing or the env var was unset — the app gates on this at launch.
    static func bundledAPIKey(bundle: Bundle = .main) -> String? {
        guard let key = bundle.object(forInfoDictionaryKey: "AnthropicAPIKey") as? String,
              !key.isEmpty else { return nil }
        return key
    }

    func stream(
        system: String,
        tools: [ToolDefinition],
        messages: [WireMessage]
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.httpBody = try JSONEncoder().encode(MessagesRequest(
                        model: Self.model,
                        maxTokens: Self.maxTokens,
                        system: system,
                        tools: tools,
                        messages: messages,
                        stream: true
                    ))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw http.statusCode >= 500 ? AgentError.server : AgentError.generic
                    }

                    // NOT bytes.lines — it swallows the blank lines that
                    // delimit SSE events (see SSELineSplitter).
                    var splitter = SSELineSplitter()
                    var parser = SSEParser()
                    var toolIDsByIndex: [Int: String] = [:]

                    func process(line: String) throws {
                        guard let event = parser.consume(line: line) else { return }
                        let payload = AnthropicStreamPayload.decode(Data(event.data.utf8))
                        if case .apiError = payload { throw AgentError.server }
                        for mapped in Self.map(payload, toolIDsByIndex: &toolIDsByIndex) {
                            continuation.yield(mapped)
                        }
                    }

                    for try await byte in bytes {
                        if let line = splitter.consume(byte: byte) {
                            try process(line: line)
                        }
                    }
                    if let tail = splitter.flush() {
                        try process(line: tail)
                    }
                    try process(line: "")  // flush any event pending at EOF
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Wire payload -> provider-neutral events. Pure (given the index map)
    /// so the regression suite can pin the mapping without networking.
    static func map(
        _ payload: AnthropicStreamPayload,
        toolIDsByIndex: inout [Int: String]
    ) -> [StreamEvent] {
        switch payload {
        case .contentBlockStartText:
            return [.textStarted]
        case .contentBlockStartToolUse(let index, let id, let name):
            toolIDsByIndex[index] = id
            return [.toolUseStarted(id: id, name: name)]
        case .textDelta(_, let text):
            return [.textDelta(text)]
        case .inputJSONDelta(let index, let partialJSON):
            guard let id = toolIDsByIndex[index] else { return [] }
            return [.toolInputDelta(id: id, partialJSON: partialJSON)]
        case .contentBlockStop(let index):
            guard let id = toolIDsByIndex.removeValue(forKey: index) else { return [] }
            return [.toolUseFinished(id: id)]
        case .messageDelta(let stopReason):
            guard let stopReason else { return [] }
            let reason: StreamEvent.StopReason = switch stopReason {
            case "end_turn": .endTurn
            case "tool_use": .toolUse
            case "max_tokens": .maxTokens
            case let other: .other(other)
            }
            return [.finished(stopReason: reason)]
        case .messageStop, .ignored, .apiError:
            return []
        }
    }
}
