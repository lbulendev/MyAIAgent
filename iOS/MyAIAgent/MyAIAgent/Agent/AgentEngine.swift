//
//  AgentEngine.swift
//  MyAIAgent
//

import Foundation
import Observation

/// One AI-worker session for one lead: owns the visible transcript, the
/// wire conversation, and the agent state machine, and drives the
/// stream -> tool -> continue loop until the model ends its turn.
///
/// Invariant the resume feature depends on: the wire conversation only ever
/// ends on a *user* message (the lead's text, a follow-up, or tool results)
/// while a run is marked interrupted — assistant blocks are appended only
/// after a stream completes. Replaying a saved conversation is therefore
/// always a valid request.
@Observable
final class AgentEngine {
    let lead: Lead
    private let provider: any ModelProvider
    private let store: CRMStore
    private let outbox: AgentOutbox

    private(set) var transcript: [ChatMessage] = []
    private(set) var state: AgentState = .idle
    private(set) var canResume = false

    private var conversation: [WireMessage] = []
    private var runTask: Task<Void, Never>?

    init(lead: Lead, provider: any ModelProvider, store: CRMStore, outbox: AgentOutbox = AgentOutbox()) {
        self.lead = lead
        self.provider = provider
        self.store = store
        self.outbox = outbox

        if let saved = outbox.load(for: lead.id) {
            conversation = saved.conversation
            transcript = saved.transcript
            canResume = saved.interrupted
        }
    }

    // MARK: Session lifecycle

    /// Starts the session on first open: the lead's message becomes the
    /// first user turn and the agent starts working it.
    func startIfNeeded() {
        guard conversation.isEmpty else { return }
        store.markLeadInProgress(id: lead.id)
        transcript.append(ChatMessage(kind: .customer, text: lead.message))
        conversation.append(.user("New \(lead.channel) lead from \(lead.customerName): \"\(lead.message)\""))
        kickoff()
    }

    /// Sends a follow-up message (spoken as the customer, keeping the demo
    /// a two-party conversation). Returns whether the message was accepted —
    /// a send while a run is in flight is refused, and the caller must keep
    /// the draft rather than dropping it.
    @discardableResult
    func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, runTask == nil else { return false }
        transcript.append(ChatMessage(kind: .customer, text: trimmed))
        conversation.append(.user(trimmed))
        kickoff()
        return true
    }

    /// Replays a conversation that was interrupted mid-run (app killed,
    /// network lost). Safe because of the ends-on-user-message invariant.
    func resume() {
        guard canResume, runTask == nil else { return }
        canResume = false
        kickoff()
    }

    /// Retry after a failure — same replay path as resume.
    func retry() {
        guard case .failed = state, runTask == nil else { return }
        kickoff()
    }

    /// Cancels the in-flight run. The saved snapshot stays resumable.
    func cancel() {
        runTask?.cancel()
    }

    private func kickoff() {
        state = .thinking
        persist(interrupted: true)
        runTask = Task { await run() }
    }

    // MARK: The agent loop

    private func run() async {
        defer { runTask = nil }
        do {
            // Keep looping while the model ends turns asking for tools.
            while true {
                let stopReason = try await streamOneTurn()
                guard stopReason == .toolUse else {
                    state = .idle
                    persist(interrupted: false)
                    return
                }
            }
        } catch is CancellationError {
            state = .idle
            canResume = true
            persist(interrupted: true)
        } catch {
            state = .failed(AgentError.categorize(error))
            persist(interrupted: true)
        }
    }

    /// Accumulates one streamed assistant turn, then — if the model called
    /// tools — executes them and appends the results as the next user turn.
    private func streamOneTurn() async throws -> StreamEvent.StopReason {
        var turn = TurnAccumulator()
        state = .thinking

        for try await event in provider.stream(
            system: Self.systemPrompt(for: lead),
            tools: ToolRegistry.definitions,
            messages: conversation
        ) {
            try Task.checkCancellation()
            handle(event, turn: &turn)
        }
        // A cancelled consumer ends the stream without throwing — check
        // explicitly so cancel() lands in the CancellationError path.
        try Task.checkCancellation()

        // A stream that completed without producing anything is a broken
        // response, not a finished turn — surface it instead of idling
        // silently. (This is how the swallowed-blank-lines SSE bug hid.)
        if turn.text.isEmpty && turn.toolCalls.isEmpty && turn.stopReason == nil {
            throw AgentError.server
        }

        // Turn complete: commit the assistant message to the conversation.
        let assistantBlocks = turn.assistantBlocks()
        if !assistantBlocks.isEmpty {
            conversation.append(WireMessage(role: "assistant", content: assistantBlocks))
        }

        if turn.stopReason == .toolUse {
            var results: [WireContentBlock] = []
            for call in turn.toolCalls {
                state = .executingTool(name: call.name)
                let outcome = ToolRegistry.execute(
                    name: call.name,
                    input: call.decodedInput(),
                    store: store,
                    leadID: lead.id
                )
                transcript.append(ChatMessage(kind: .toolActivity, text: outcome.activity))
                results.append(.toolResult(toolUseID: call.id, content: outcome.result, isError: outcome.isError))
            }
            // All results go back in a single user message, per the API contract.
            conversation.append(WireMessage(role: "user", content: results))
            persist(interrupted: true)
        }

        return turn.stopReason ?? .endTurn
    }

    /// Applies one stream event to UI state and the turn accumulator.
    /// Internal (not private) so tests can drive the state machine directly.
    func handle(_ event: StreamEvent, turn: inout TurnAccumulator) {
        switch event {
        case .textStarted:
            state = .streaming
            turn.streamingMessageID = transcript.appendAgentMessage()
        case .textDelta(let text):
            turn.text += text
            if let id = turn.streamingMessageID {
                transcript.appendText(text, toMessageWithID: id)
            }
        case .toolUseStarted(let id, let name):
            state = .executingTool(name: name)
            turn.toolCalls.append(TurnAccumulator.ToolCall(id: id, name: name, inputJSON: ""))
        case .toolInputDelta(let id, let partialJSON):
            if let index = turn.toolCalls.firstIndex(where: { $0.id == id }) {
                turn.toolCalls[index].inputJSON += partialJSON
            }
        case .toolUseFinished:
            break
        case .finished(let stopReason):
            turn.stopReason = stopReason
        }
    }

    private func persist(interrupted: Bool) {
        outbox.save(
            AgentOutbox.SessionSnapshot(conversation: conversation, transcript: transcript, interrupted: interrupted),
            for: lead.id
        )
    }

    // MARK: Prompt

    static nonisolated func systemPrompt(for lead: Lead) -> String {
        """
        You are the AI worker for Beagle Bike Shop, a local bicycle sales and \
        repair shop. You handle inbound customer leads end to end: answer the \
        customer, look up their record, book appointments, and close out the \
        lead when it is resolved.

        Rules:
        - Reply to the customer in one to three friendly, concise sentences.
        - Use lookup_customer before booking so you know if they are an \
        existing customer.
        - Only book after the customer has named a service and a day; \
        otherwise ask.
        - After booking a service appointment, use send_payment_link to \
        collect the shop's standard $20 deposit, and tell the customer the \
        link is on its way. Never ask for card details in chat.
        - The shop is open Tuesday through Saturday, 9am to 6pm.
        - When the request is fully resolved, call mark_lead_handled with a \
        one-sentence summary.

        Current lead: \(lead.customerName) via \(lead.channel).
        """
    }
}

/// Accumulates the pieces of one streamed assistant turn in arrival order.
nonisolated struct TurnAccumulator {
    struct ToolCall: Equatable {
        let id: String
        let name: String
        var inputJSON: String

        /// The API streams tool input as partial JSON; empty means {}.
        func decodedInput() -> JSONValue {
            let json = inputJSON.isEmpty ? "{}" : inputJSON
            return (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .object([:])
        }
    }

    var text = ""
    var toolCalls: [ToolCall] = []
    var stopReason: StreamEvent.StopReason?
    var streamingMessageID: UUID?

    /// Wire blocks for the assistant message, text first then tool calls —
    /// matching the order the model produced them.
    func assistantBlocks() -> [WireContentBlock] {
        var blocks: [WireContentBlock] = []
        if !text.isEmpty { blocks.append(.text(text)) }
        for call in toolCalls {
            blocks.append(.toolUse(id: call.id, name: call.name, input: call.decodedInput()))
        }
        return blocks
    }
}

private extension [ChatMessage] {
    /// Appends an empty agent message and returns its id for streaming into.
    mutating func appendAgentMessage() -> UUID {
        let message = ChatMessage(kind: .agent, text: "")
        append(message)
        return message.id
    }

    mutating func appendText(_ text: String, toMessageWithID id: UUID) {
        guard let index = lastIndex(where: { $0.id == id }) else { return }
        self[index].text += text
    }
}
