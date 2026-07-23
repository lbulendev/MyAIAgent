//
//  SSEParser.swift
//  MyAIAgent
//

import Foundation

/// Incremental Server-Sent Events parser. Feed it lines (in any chunking);
/// it emits complete events. Pure and synchronous so the regression suite
/// can pin edge cases — split chunks, blank keep-alives, missing fields —
/// without any networking.
nonisolated struct SSEParser {
    nonisolated struct Event: Equatable {
        var name: String?
        var data: String
    }

    private var currentName: String?
    private var currentData: [String] = []

    /// Consume one line (without its trailing newline). Returns a completed
    /// event when the line is the blank separator, nil otherwise.
    mutating func consume(line: String) -> Event? {
        if line.isEmpty {
            defer { currentName = nil; currentData = [] }
            guard !currentData.isEmpty else { return nil }
            return Event(name: currentName, data: currentData.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }  // comment / keep-alive

        let field: Substring
        let value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[line.startIndex..<colon]
            var rest = line[line.index(after: colon)...]
            if rest.hasPrefix(" ") { rest = rest.dropFirst() }
            value = rest
        } else {
            field = line[...]
            value = ""
        }

        switch field {
        case "event": currentName = String(value)
        case "data": currentData.append(String(value))
        default: break  // id, retry, unknown fields — not used
        }
        return nil
    }
}

/// Splits a raw byte stream into lines INCLUDING empty ones.
/// `URLSession.AsyncBytes.lines` silently swallows blank lines — and blank
/// lines are the SSE event delimiter, so using it starves `SSEParser` and
/// every stream "completes" with zero events. Split bytes manually.
nonisolated struct SSELineSplitter {
    private var buffer: [UInt8] = []

    /// Consume one byte; returns a completed line (without terminator)
    /// when the byte is a newline. Tolerates CRLF.
    mutating func consume(byte: UInt8) -> String? {
        if byte == UInt8(ascii: "\n") {
            if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
            defer { buffer.removeAll(keepingCapacity: true) }
            return String(decoding: buffer, as: UTF8.self)
        }
        buffer.append(byte)
        return nil
    }

    /// Any trailing bytes after the stream ends (no final newline).
    mutating func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
        defer { buffer.removeAll() }
        return String(decoding: buffer, as: UTF8.self)
    }
}
