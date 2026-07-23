package com.curiousbeagle.android.myaiagent.agent

import com.curiousbeagle.android.myaiagent.model.AgentError
import com.curiousbeagle.android.myaiagent.model.AgentState
import com.curiousbeagle.android.myaiagent.model.ChatMessage
import com.curiousbeagle.android.myaiagent.model.CrmStore
import com.curiousbeagle.android.myaiagent.model.Lead
import com.curiousbeagle.android.myaiagent.net.ModelProvider
import com.curiousbeagle.android.myaiagent.net.StreamEvent
import com.curiousbeagle.android.myaiagent.net.WireContentBlock
import com.curiousbeagle.android.myaiagent.net.WireMessage
import com.curiousbeagle.android.myaiagent.net.wireJson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject

/**
 * One AI-worker session for one lead, mirroring iOS `AgentEngine`: owns the
 * visible transcript, the wire conversation, and the agent state machine,
 * and drives the stream -> tool -> continue loop until the model ends its
 * turn. Plain class with an injected scope (the HeartChart monitor pattern)
 * so it is app-scoped — surviving rotation — and testable with a test scope.
 *
 * Invariant the resume feature depends on: the wire conversation only ever
 * ends on a *user* message while a run is marked interrupted — assistant
 * blocks are appended only after a stream completes. Replaying a saved
 * conversation is therefore always a valid request.
 */
class AgentEngine(
    val lead: Lead,
    private val provider: ModelProvider,
    private val store: CrmStore,
    private val outbox: AgentOutbox,
    private val scope: CoroutineScope,
) {
    private val _transcript = MutableStateFlow<List<ChatMessage>>(emptyList())
    val transcript: StateFlow<List<ChatMessage>> = _transcript.asStateFlow()

    private val _state = MutableStateFlow<AgentState>(AgentState.Idle)
    val state: StateFlow<AgentState> = _state.asStateFlow()

    private val _canResume = MutableStateFlow(false)
    val canResume: StateFlow<Boolean> = _canResume.asStateFlow()

    private var conversation = mutableListOf<WireMessage>()
    private var runJob: Job? = null

    init {
        outbox.load(lead.id)?.let { saved ->
            conversation = saved.conversation.toMutableList()
            _transcript.value = saved.transcript
            _canResume.value = saved.interrupted
        }
    }

    /** Starts the session on first open: the lead's message becomes the first user turn. */
    fun startIfNeeded() {
        if (conversation.isNotEmpty()) return
        store.markLeadInProgress(lead.id)
        appendMessage(ChatMessage(kind = ChatMessage.Kind.CUSTOMER, text = lead.message))
        conversation += WireMessage.user("New ${lead.channel} lead from ${lead.customerName}: \"${lead.message}\"")
        kickoff()
    }

    /** Sends a follow-up message (spoken as the customer). */
    fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || runJob?.isActive == true) return
        appendMessage(ChatMessage(kind = ChatMessage.Kind.CUSTOMER, text = trimmed))
        conversation += WireMessage.user(trimmed)
        kickoff()
    }

    /** Replays a conversation that was interrupted mid-run. */
    fun resume() {
        if (!_canResume.value || runJob?.isActive == true) return
        _canResume.value = false
        kickoff()
    }

    /** Retry after a failure — same replay path as resume. */
    fun retry() {
        if (_state.value !is AgentState.Failed || runJob?.isActive == true) return
        kickoff()
    }

    /** Cancels the in-flight run. The saved snapshot stays resumable. */
    fun cancel() {
        runJob?.cancel()
    }

    private fun kickoff() {
        _state.value = AgentState.Thinking
        persist(interrupted = true)
        runJob = scope.launch { run() }
    }

    private suspend fun run() {
        try {
            // Keep looping while the model ends turns asking for tools.
            while (true) {
                val stopReason = streamOneTurn()
                if (stopReason != StreamEvent.StopReason.ToolUse) {
                    _state.value = AgentState.Idle
                    persist(interrupted = false)
                    return
                }
            }
        } catch (e: CancellationException) {
            // ALWAYS rethrow cancellation — but first record the resumable state.
            _state.value = AgentState.Idle
            _canResume.value = true
            persist(interrupted = true)
            throw e
        } catch (e: Exception) {
            _state.value = AgentState.Failed(AgentError.categorize(e))
            persist(interrupted = true)
        }
    }

    /**
     * Accumulates one streamed assistant turn, then — if the model called
     * tools — executes them and appends the results as the next user turn.
     */
    private suspend fun streamOneTurn(): StreamEvent.StopReason {
        val turn = TurnAccumulator()
        _state.value = AgentState.Thinking

        provider.stream(systemPrompt(lead), ToolRegistry.definitions, conversation.toList())
            .collect { event -> handle(event, turn) }

        // A stream that completed without producing anything is a broken
        // response, not a finished turn — surface it instead of idling silently.
        if (turn.text.isEmpty() && turn.toolCalls.isEmpty() && turn.stopReason == null) {
            throw com.curiousbeagle.android.myaiagent.model.AgentFailure(AgentError.SERVER)
        }

        // Turn complete: commit the assistant message to the conversation.
        val assistantBlocks = turn.assistantBlocks()
        if (assistantBlocks.isNotEmpty()) {
            conversation += WireMessage("assistant", assistantBlocks)
        }

        if (turn.stopReason == StreamEvent.StopReason.ToolUse) {
            val results = mutableListOf<WireContentBlock>()
            for (call in turn.toolCalls) {
                _state.value = AgentState.ExecutingTool(call.name)
                val outcome = ToolRegistry.execute(call.name, call.decodedInput(), store, lead.id)
                appendMessage(ChatMessage(kind = ChatMessage.Kind.TOOL_ACTIVITY, text = outcome.activity))
                results += WireContentBlock.ToolResult(call.id, outcome.result, outcome.isError)
            }
            // All results go back in a single user message, per the API contract.
            conversation += WireMessage("user", results)
            persist(interrupted = true)
        }

        return turn.stopReason ?: StreamEvent.StopReason.EndTurn
    }

    /**
     * Applies one stream event to UI state and the turn accumulator.
     * Internal so tests can drive the state machine directly.
     */
    internal fun handle(event: StreamEvent, turn: TurnAccumulator) {
        when (event) {
            StreamEvent.TextStarted -> {
                _state.value = AgentState.Streaming
                val message = ChatMessage(kind = ChatMessage.Kind.AGENT, text = "")
                turn.streamingMessageId = message.id
                appendMessage(message)
            }
            is StreamEvent.TextDelta -> {
                turn.text += event.text
                turn.streamingMessageId?.let { id ->
                    _transcript.update { list ->
                        list.map { if (it.id == id) it.copy(text = it.text + event.text) else it }
                    }
                }
            }
            is StreamEvent.ToolUseStarted -> {
                _state.value = AgentState.ExecutingTool(event.name)
                turn.toolCalls += TurnAccumulator.ToolCall(event.id, event.name, "")
            }
            is StreamEvent.ToolInputDelta -> {
                val index = turn.toolCalls.indexOfFirst { it.id == event.id }
                if (index >= 0) {
                    val call = turn.toolCalls[index]
                    turn.toolCalls[index] = call.copy(inputJson = call.inputJson + event.partialJson)
                }
            }
            is StreamEvent.ToolUseFinished -> Unit
            is StreamEvent.Finished -> turn.stopReason = event.stopReason
        }
    }

    private fun appendMessage(message: ChatMessage) {
        _transcript.update { it + message }
    }

    private fun persist(interrupted: Boolean) {
        outbox.save(
            AgentOutbox.SessionSnapshot(conversation.toList(), _transcript.value, interrupted),
            lead.id,
        )
    }

    companion object {
        fun systemPrompt(lead: Lead): String = """
            You are the AI worker for Beagle Bike Shop, a local bicycle sales and repair shop. You handle inbound customer leads end to end: answer the customer, look up their record, book appointments, and close out the lead when it is resolved.

            Rules:
            - Reply to the customer in one to three friendly, concise sentences.
            - Use lookup_customer before booking so you know if they are an existing customer.
            - Only book after the customer has named a service and a day; otherwise ask.
            - The shop is open Tuesday through Saturday, 9am to 6pm.
            - When the request is fully resolved, call mark_lead_handled with a one-sentence summary.

            Current lead: ${lead.customerName} via ${lead.channel}.
        """.trimIndent()
    }
}

/** Accumulates the pieces of one streamed assistant turn in arrival order. */
internal class TurnAccumulator {
    data class ToolCall(val id: String, val name: String, val inputJson: String) {
        /** The API streams tool input as partial JSON; empty means {}. */
        fun decodedInput(): JsonObject = runCatching {
            wireJson.parseToJsonElement(inputJson.ifEmpty { "{}" }) as JsonObject
        }.getOrDefault(buildJsonObject {})
    }

    var text = ""
    val toolCalls = mutableListOf<ToolCall>()
    var stopReason: StreamEvent.StopReason? = null
    var streamingMessageId: String? = null

    /** Wire blocks for the assistant message, text first then tool calls. */
    fun assistantBlocks(): List<WireContentBlock> = buildList {
        if (text.isNotEmpty()) add(WireContentBlock.Text(text))
        toolCalls.forEach { add(WireContentBlock.ToolUse(it.id, it.name, it.decodedInput())) }
    }
}
