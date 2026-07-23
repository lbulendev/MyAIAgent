//
//  AnthropicWire.swift
//  MyAIAgent
//
//  Codable types for the Anthropic Messages API (streaming + client tools).
//  Kept wire-faithful and minimal: only the fields this app sends or reads.
//

import Foundation

/// Arbitrary JSON — tool inputs and schemas are model-defined shapes.
nonisolated enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Convenience accessor for `.object` string fields (tool inputs).
    subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }
}

// MARK: Request

nonisolated struct ToolDefinition: Codable, Equatable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

/// One content block inside a wire message. The same enum covers what we
/// send (text, tool_result) and what we echo back from the assistant
/// (text, tool_use).
nonisolated enum WireContentBlock: Codable, Equatable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, content
        case toolUseID = "tool_use_id"
        case isError = "is_error"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                input: try container.decode(JSONValue.self, forKey: .input)
            )
        case "tool_result":
            self = .toolResult(
                toolUseID: try container.decode(String.self, forKey: .toolUseID),
                content: try container.decode(String.self, forKey: .content),
                isError: try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            )
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown block type \(other)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError { try container.encode(true, forKey: .isError) }
        }
    }
}

nonisolated struct WireMessage: Codable, Equatable {
    let role: String
    let content: [WireContentBlock]

    static func user(_ text: String) -> WireMessage {
        WireMessage(role: "user", content: [.text(text)])
    }
}

nonisolated struct MessagesRequest: Codable {
    let model: String
    let maxTokens: Int
    let system: String
    let tools: [ToolDefinition]
    let messages: [WireMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, system, tools, messages, stream
        case maxTokens = "max_tokens"
    }
}

// MARK: Streaming events (decoded from SSE `data:` payloads)

/// Raw stream payloads. `SSEParser` splits the byte stream into events;
/// this decodes each `data:` JSON by its `type` discriminator.
nonisolated enum AnthropicStreamPayload: Equatable {
    case contentBlockStartText(index: Int)
    case contentBlockStartToolUse(index: Int, id: String, name: String)
    case textDelta(index: Int, text: String)
    case inputJSONDelta(index: Int, partialJSON: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?)
    case messageStop
    case ignored          // message_start, ping, thinking deltas, unknown-but-harmless
    case apiError(message: String)

    /// Tolerant decode: unknown event types are `.ignored`, not an error —
    /// the API adds event types over time and old clients must not break.
    static func decode(_ data: Data) -> AnthropicStreamPayload {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .apiError(message: "undecodable stream payload")
        }
        switch type {
        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any],
                  let blockType = block["type"] as? String else { return .ignored }
            if blockType == "text" { return .contentBlockStartText(index: index) }
            if blockType == "tool_use",
               let id = block["id"] as? String,
               let name = block["name"] as? String {
                return .contentBlockStartToolUse(index: index, id: id, name: name)
            }
            return .ignored
        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return .ignored }
            if deltaType == "text_delta", let text = delta["text"] as? String {
                return .textDelta(index: index, text: text)
            }
            if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                return .inputJSONDelta(index: index, partialJSON: partial)
            }
            return .ignored
        case "content_block_stop":
            guard let index = json["index"] as? Int else { return .ignored }
            return .contentBlockStop(index: index)
        case "message_delta":
            let delta = json["delta"] as? [String: Any]
            return .messageDelta(stopReason: delta?["stop_reason"] as? String)
        case "message_stop":
            return .messageStop
        case "error":
            let error = json["error"] as? [String: Any]
            return .apiError(message: error?["message"] as? String ?? "stream error")
        default:
            return .ignored
        }
    }
}
