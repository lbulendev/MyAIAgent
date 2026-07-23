package com.curiousbeagle.android.myaiagent

import com.curiousbeagle.android.myaiagent.agent.AgentEngine
import com.curiousbeagle.android.myaiagent.agent.AgentOutbox
import com.curiousbeagle.android.myaiagent.model.CrmStore
import com.curiousbeagle.android.myaiagent.model.Lead
import com.curiousbeagle.android.myaiagent.net.ModelProvider
import com.curiousbeagle.android.myaiagent.net.StreamEvent
import com.curiousbeagle.android.myaiagent.net.ToolDefinition
import com.curiousbeagle.android.myaiagent.net.WireMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.io.File
import kotlin.io.path.createTempDirectory

/**
 * Scripted stand-in at the network boundary, mirroring the iOS
 * `FakeModelProvider`. Each `stream()` call consumes the next scripted turn
 * and records the request, so tests can assert on the exact wire
 * conversation the engine sent. Single-threaded test dispatchers make the
 * plain lists safe.
 */
class FakeModelProvider(script: List<ScriptedTurn>) : ModelProvider {

    sealed interface ScriptedTurn {
        data class Events(val events: List<StreamEvent>) : ScriptedTurn
        data class Failure(val throwable: Throwable) : ScriptedTurn

        /** A stream that never produces or finishes — for cancellation tests. */
        data object Hang : ScriptedTurn

        companion object {
            /** A plain streamed text reply ending the turn. */
            fun textTurn(text: String) = Events(
                listOf(
                    StreamEvent.TextStarted,
                    StreamEvent.TextDelta(text),
                    StreamEvent.Finished(StreamEvent.StopReason.EndTurn),
                )
            )

            /** A turn where the model calls one tool with the given JSON input. */
            fun toolTurn(id: String, name: String, inputJson: String) = Events(
                listOf(
                    StreamEvent.ToolUseStarted(id, name),
                    StreamEvent.ToolInputDelta(id, inputJson),
                    StreamEvent.ToolUseFinished(id),
                    StreamEvent.Finished(StreamEvent.StopReason.ToolUse),
                )
            )
        }
    }

    private val remaining = script.toMutableList()
    val recordedRequests = mutableListOf<List<WireMessage>>()

    override fun stream(
        system: String,
        tools: List<ToolDefinition>,
        messages: List<WireMessage>,
    ): Flow<StreamEvent> = flow {
        recordedRequests += messages
        when (val turn = if (remaining.isEmpty()) null else remaining.removeAt(0)) {
            is ScriptedTurn.Events -> turn.events.forEach { emit(it) }
            is ScriptedTurn.Failure -> throw turn.throwable
            ScriptedTurn.Hang -> awaitCancellation()
            null -> throw IllegalStateException("script exhausted")
        }
    }
}

/** Isolated per-test storage so persistence tests never interfere. */
fun temporaryOutboxDirectory(): File = createTempDirectory("outbox-tests").toFile()

fun makeEngine(
    scope: CoroutineScope,
    provider: FakeModelProvider,
    lead: Lead = Lead.sample,
    store: CrmStore = CrmStore(listOf(lead)),
    outbox: AgentOutbox = AgentOutbox(temporaryOutboxDirectory()),
): Triple<AgentEngine, CrmStore, AgentOutbox> {
    val engine = AgentEngine(lead, provider, store, outbox, scope)
    return Triple(engine, store, outbox)
}
