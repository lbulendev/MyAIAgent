//
//  RegressionTests.swift
//  MyAIAgentTests
//

import Foundation
import Testing
@testable import MyAIAgent

// Pinned edge cases, each documenting the failure it prevents.
@Suite("Regression", .tags(.regression))
struct RegressionTests {

    // MARK: SSE parsing

    @Suite("SSE parser", .tags(.parsing))
    struct SSE {
        @Test("Multi-line data fields join with newlines (spec-required)")
        func multiLineData() {
            var parser = SSEParser()
            #expect(parser.consume(line: "event: message_delta") == nil)
            #expect(parser.consume(line: "data: {\"a\":") == nil)
            #expect(parser.consume(line: "data: 1}") == nil)
            let event = parser.consume(line: "")
            #expect(event == SSEParser.Event(name: "message_delta", data: "{\"a\":\n1}"))
        }

        @Test("Keep-alive comments and unknown fields are ignored, not events")
        func keepAlives() {
            var parser = SSEParser()
            #expect(parser.consume(line: ": keep-alive") == nil)
            #expect(parser.consume(line: "id: 42") == nil)
            #expect(parser.consume(line: "") == nil)  // blank with no data: no phantom event
        }

        @Test("The byte splitter preserves blank lines — URLSession's .lines swallows them and starves the parser (the silent-no-reply bug)")
        func blankLinesSurvive() {
            var splitter = SSELineSplitter()
            var lines: [String] = []
            for byte in Array("event: message_stop\r\ndata: {}\r\n\r\n".utf8) {
                if let line = splitter.consume(byte: byte) { lines.append(line) }
            }
            // Three lines, the last one EMPTY — that's the event delimiter.
            #expect(lines == ["event: message_stop", "data: {}", ""])
        }

        @Test("A stream tail without a final newline still flushes")
        func tailFlushes() {
            var splitter = SSELineSplitter()
            for byte in Array("data: {\"a\":1}".utf8) {
                _ = splitter.consume(byte: byte)
            }
            #expect(splitter.flush() == "data: {\"a\":1}")
            #expect(splitter.flush() == nil)
        }

        @Test("Back-to-back events don't leak state into each other")
        func consecutiveEvents() {
            var parser = SSEParser()
            _ = parser.consume(line: "event: one")
            _ = parser.consume(line: "data: 1")
            let first = parser.consume(line: "")
            _ = parser.consume(line: "data: 2")
            let second = parser.consume(line: "")
            #expect(first?.name == "one")
            #expect(second?.name == nil)  // name must not carry over
            #expect(second?.data == "2")
        }
    }

    // MARK: Stream payload decoding

    @Suite("Stream payloads", .tags(.parsing))
    struct Payloads {
        @Test("Unknown event types are tolerated — new API events must not break old clients")
        func unknownTypesIgnored() {
            let payload = AnthropicStreamPayload.decode(Data(#"{"type": "brand_new_event"}"#.utf8))
            #expect(payload == .ignored)
        }

        @Test("Undecodable payloads surface as errors, never crash")
        func malformedPayload() {
            let payload = AnthropicStreamPayload.decode(Data("not json".utf8))
            #expect(payload == .apiError(message: "undecodable stream payload"))
        }

        @Test("Tool-use start and input deltas decode with their indices")
        func toolUseDecoding() {
            let start = AnthropicStreamPayload.decode(Data(
                #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_9","name":"book_appointment","input":{}}}"#.utf8
            ))
            #expect(start == .contentBlockStartToolUse(index: 1, id: "tu_9", name: "book_appointment"))

            let delta = AnthropicStreamPayload.decode(Data(
                #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"day\""}}"#.utf8
            ))
            #expect(delta == .inputJSONDelta(index: 1, partialJSON: #"{"day""#))
        }

        @Test("Input deltas for an unknown block index are dropped, not crashed on")
        func orphanInputDelta() {
            var toolIDs: [Int: String] = [:]
            let events = ClaudeProvider.map(.inputJSONDelta(index: 7, partialJSON: "{}"), toolIDsByIndex: &toolIDs)
            #expect(events.isEmpty)
        }
    }

    // MARK: Turn accumulation

    @Suite("Turn accumulator", .tags(.agent))
    struct Turns {
        @Test("Tool input split across deltas reassembles into valid JSON")
        func partialJSONReassembly() {
            var call = TurnAccumulator.ToolCall(id: "tu_1", name: "book_appointment", inputJSON: "")
            call.inputJSON += #"{"customer_name": "Da"#
            call.inputJSON += #"na Reyes", "service": "tune-up", "day": "Thursday"}"#
            let input = call.decodedInput()
            #expect(input["customer_name"]?.stringValue == "Dana Reyes")
            #expect(input["day"]?.stringValue == "Thursday")
        }

        @Test("Empty tool input decodes as an empty object, not a decode failure")
        func emptyInput() {
            let call = TurnAccumulator.ToolCall(id: "tu_1", name: "mark_lead_handled", inputJSON: "")
            #expect(call.decodedInput() == .object([:]))
        }

        @Test("Assistant blocks keep model order: text first, then tool calls")
        func blockOrder() {
            var turn = TurnAccumulator()
            turn.text = "Let me check."
            turn.toolCalls = [TurnAccumulator.ToolCall(id: "tu_1", name: "lookup_customer", inputJSON: #"{"name":"Dana"}"#)]
            let blocks = turn.assistantBlocks()
            #expect(blocks.count == 2)
            if case .text(let text) = blocks[0] { #expect(text == "Let me check.") } else { Issue.record("expected text block first") }
            if case .toolUse(let id, _, _) = blocks[1] { #expect(id == "tu_1") } else { Issue.record("expected tool_use block second") }
        }
    }

    // MARK: Catalog decode (ADR 0001: tolerant decode)

    @Suite("Catalog decode", .tags(.catalog))
    struct CatalogDecode {
        private func decode(_ json: String) throws -> HelpCatalog {
            try JSONDecoder().decode(HelpCatalog.self, from: Data(json.utf8))
        }

        @Test("An unknown entry kind is skipped, not a decode failure — new content kinds must not break old clients")
        func unknownKindSkipped() throws {
            let catalog = try decode(#"""
            {"version": 1, "entries": [
                {"kind": "hologram_demo", "id": "holo", "title": "Hologram"},
                {"kind": "help_article", "id": "a", "title": "A", "steps": ["one"]}
            ]}
            """#)
            #expect(catalog.entries.map(\.id) == ["a"])
        }

        @Test("An unknown requires value is never presented as available offline")
        func unknownRequirementIsOnlineOnly() throws {
            let catalog = try decode(#"""
            {"version": 1, "entries": [
                {"kind": "service", "id": "s", "title": "S", "requires": "bluetooth"}
            ]}
            """#)
            #expect(catalog.entries.first?.requirement == .online)
            #expect(catalog.entries.first?.isAvailable(online: false) == false)
        }

        @Test("Unknown fields and missing optionals are tolerated — content can evolve ahead of shipped clients")
        func unknownFieldsIgnored() throws {
            let catalog = try decode(#"""
            {"version": 2, "future_field": {"nested": true}, "entries": [
                {"kind": "help_article", "id": "a", "title": "A", "video_url": "https://example.com"}
            ]}
            """#)
            let entry = try #require(catalog.entries.first)
            #expect(entry.summary == "")
            #expect(entry.keywords.isEmpty)
            #expect(entry.steps.isEmpty)
            #expect(entry.requirement == .none)
        }
    }

    // MARK: Persistence & resume

    @Suite("Outbox", .tags(.persistence))
    @MainActor
    struct Outbox {
        @Test("Snapshots round-trip through disk")
        func roundTrip() {
            let outbox = AgentOutbox(directory: temporaryOutboxDirectory())
            let leadID = UUID()
            let snapshot = AgentOutbox.SessionSnapshot(
                conversation: [.user("hello")],
                transcript: [ChatMessage(kind: .customer, text: "hello")],
                interrupted: true
            )
            outbox.save(snapshot, for: leadID)
            #expect(outbox.load(for: leadID) == snapshot)
            outbox.clear(for: leadID)
            #expect(outbox.load(for: leadID) == nil)
        }

        @Test("offlineHelp transcript entries round-trip — the shared snapshot format gained a message kind and Android must mirror it")
        func offlineHelpKindRoundTrips() {
            let outbox = AgentOutbox(directory: temporaryOutboxDirectory())
            let leadID = UUID()
            let snapshot = AgentOutbox.SessionSnapshot(
                conversation: [.user("how do I fix a flat?")],
                transcript: [
                    ChatMessage(kind: .customer, text: "how do I fix a flat?"),
                    ChatMessage(kind: .offlineHelp, text: "Fix a flat tire\n1. Remove the wheel…"),
                ],
                interrupted: true
            )
            outbox.save(snapshot, for: leadID)
            #expect(outbox.load(for: leadID) == snapshot)
        }

        @Test("An interrupted session restores as resumable and replays a user-terminated conversation")
        func resumeReplaysConversation() async throws {
            let lead = Lead.sample
            let directory = temporaryOutboxDirectory()
            let outbox = AgentOutbox(directory: directory)

            // Simulate an app death mid-run: conversation saved, interrupted.
            outbox.save(AgentOutbox.SessionSnapshot(
                conversation: [.user("New SMS lead from Dana Reyes: \"help\"")],
                transcript: [ChatMessage(kind: .customer, text: "help")],
                interrupted: true
            ), for: lead.id)

            let provider = FakeModelProvider(script: [.textTurn("Picking this back up!")])
            let store = CRMStore(leads: [lead])
            let engine = AgentEngine(lead: lead, provider: provider, store: store, outbox: AgentOutbox(directory: directory))

            #expect(engine.canResume)
            engine.resume()
            try await waitUntil { engine.state == .idle && engine.transcript.count == 2 }

            // The replayed request is the saved conversation, ending on the user turn.
            let request = try #require(provider.recordedRequests.first)
            #expect(request.last?.role == "user")
            #expect(engine.canResume == false)
        }
    }

    // MARK: Offline responder (ADR 0001: labeled local replies, store-and-forward)

    @Suite("Offline responder", .tags(.agent))
    @MainActor
    struct OfflineResponder {
        @Test("Responder replies never enter the wire conversation — the model must not be attributed words it didn't say")
        func repliesStayOutOfWire() throws {
            let provider = FakeModelProvider(script: [])
            let (engine, _, outbox) = makeEngine(provider: provider)

            engine.startOfflineIfNeeded()
            engine.sendWhileOffline("how do I fix a flat tire?")

            let snapshot = try #require(outbox.load(for: engine.lead.id))
            #expect(snapshot.interrupted)
            #expect(snapshot.conversation.allSatisfy { $0.role == "user" })
            #expect(snapshot.conversation.last?.role == "user")
            // The guide text reached the transcript, not the wire.
            #expect(engine.transcript.contains { $0.kind == .offlineHelp && $0.text.contains("Fix a flat tire") })
        }

        @Test("Questions asked offline replay to the real agent on resume — store-and-forward via the resume invariant")
        func offlineQuestionsReplayOnResume() async throws {
            let provider = FakeModelProvider(script: [.textTurn("Back online — happy to book that flat fix!")])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.startOfflineIfNeeded()
            engine.sendWhileOffline("how do I fix a flat tire?")
            #expect(engine.canResume)

            engine.resume()
            try await waitUntil { engine.state == .idle && engine.transcript.last?.kind == .agent }

            let request = try #require(provider.recordedRequests.first)
            #expect(request.allSatisfy { $0.role == "user" })
            #expect(request.contains { message in
                message.content.contains { block in
                    if case .text(let text) = block { return text.contains("flat tire") }
                    return false
                }
            })
        }

        @Test("A run cancelled by a connectivity drop hands off to the offline responder — the chat must never freeze on a dead stream")
        func cancelledRunHandsOffToResponder() async throws {
            let provider = FakeModelProvider(script: [.hang])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.startIfNeeded()
            try await waitUntil {
                if case .thinking = engine.state { return true }
                return false
            }

            // What the view does when isOnline flips to false mid-run.
            engine.cancel()
            try await waitUntil { engine.state == .idle }

            #expect(engine.sendWhileOffline("how do I fix a flat tire?"))
            #expect(engine.transcript.last?.kind == .offlineHelp)
            #expect(engine.transcript.last?.text.contains("Fix a flat tire") == true)
        }

        @Test("No matching guide gets the honest no-match reply plus the list of available guides — asking 'what guides do you have?' never dead-ends")
        func noMatchIsHonest() throws {
            let provider = FakeModelProvider(script: [])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.sendWhileOffline("xylophone lessons")

            let reply = try #require(engine.transcript.last)
            #expect(reply.kind == .offlineHelp)
            #expect(reply.text.contains("No offline guide"))
            #expect(reply.text.contains("• Fix a flat tire"))
        }
    }

    // MARK: Failure and cancellation

    @Suite("Failure paths", .tags(.agent))
    @MainActor
    struct FailurePaths {
        @Test("A connectivity failure surfaces as the offline category and retry replays the run")
        func offlineThenRetry() async throws {
            let provider = FakeModelProvider(script: [
                .failure(URLError(.notConnectedToInternet)),
                .textTurn("Back online — happy to help!"),
            ])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.startIfNeeded()
            try await waitUntil { engine.state == .failed(.offline) }

            engine.retry()
            try await waitUntil { engine.state == .idle && engine.transcript.count == 2 }
            #expect(engine.transcript.last?.text == "Back online — happy to help!")
        }

        @Test("A stream that completes with zero events fails loudly — never a silent idle with no reply")
        func emptyStreamSurfacesError() async throws {
            let provider = FakeModelProvider(script: [.events([])])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.startIfNeeded()
            try await waitUntil { engine.state == .failed(.server) }
        }

        @Test("A send while the agent is running is refused, not silently dropped")
        func sendWhileRunningRefused() async throws {
            let provider = FakeModelProvider(script: [.hang])
            let (engine, _, _) = makeEngine(provider: provider)

            engine.startIfNeeded()
            try await waitUntil {
                if case .thinking = engine.state { return true }
                return false
            }

            // The composer keeps the draft when this returns false.
            #expect(engine.send("yes, on tuesday") == false)
            #expect(engine.transcript.first(where: { $0.text == "yes, on tuesday" }) == nil)

            engine.cancel()
            try await waitUntil { engine.state == .idle }
        }

        @Test("Cancel mid-stream leaves the session idle and resumable — never a spinner or a crash")
        func cancelIsResumable() async throws {
            let provider = FakeModelProvider(script: [.hang])
            let (engine, _, outbox) = makeEngine(provider: provider)

            engine.startIfNeeded()
            try await waitUntil {
                if case .thinking = engine.state { return true }
                return false
            }

            engine.cancel()
            try await waitUntil { engine.state == .idle }
            #expect(engine.canResume)
            #expect(outbox.load(for: engine.lead.id)?.interrupted == true)
        }
    }
}
