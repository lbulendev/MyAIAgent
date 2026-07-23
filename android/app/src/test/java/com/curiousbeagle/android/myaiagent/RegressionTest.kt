package com.curiousbeagle.android.myaiagent

import com.curiousbeagle.android.myaiagent.FakeModelProvider.ScriptedTurn
import com.curiousbeagle.android.myaiagent.agent.AgentEngine
import com.curiousbeagle.android.myaiagent.agent.AgentOutbox
import com.curiousbeagle.android.myaiagent.agent.TurnAccumulator
import com.curiousbeagle.android.myaiagent.model.AgentError
import com.curiousbeagle.android.myaiagent.model.AgentState
import com.curiousbeagle.android.myaiagent.model.ChatMessage
import com.curiousbeagle.android.myaiagent.model.CrmStore
import com.curiousbeagle.android.myaiagent.model.Lead
import com.curiousbeagle.android.myaiagent.net.AnthropicStreamPayload
import com.curiousbeagle.android.myaiagent.net.ClaudeProvider
import com.curiousbeagle.android.myaiagent.net.SseParser
import com.curiousbeagle.android.myaiagent.net.WireContentBlock
import com.curiousbeagle.android.myaiagent.net.WireMessage
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import okio.Buffer
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import java.net.UnknownHostException

/** Pinned edge cases mirroring the iOS RegressionTests, each documenting the failure it prevents. */
@Tag("regression")
class RegressionTest {

    @Nested
    @Tag("parsing")
    inner class Sse {

        @Test
        fun `multi-line data fields join with newlines (spec-required)`() {
            val parser = SseParser()
            assertNull(parser.consume("event: message_delta"))
            assertNull(parser.consume("data: {\"a\":"))
            assertNull(parser.consume("data: 1}"))
            assertEquals(SseParser.Event("message_delta", "{\"a\":\n1}"), parser.consume(""))
        }

        @Test
        fun `keep-alive comments and unknown fields are ignored, not events`() {
            val parser = SseParser()
            assertNull(parser.consume(": keep-alive"))
            assertNull(parser.consume("id: 42"))
            assertNull(parser.consume("")) // blank with no data: no phantom event
        }

        @Test
        fun `back-to-back events don't leak state into each other`() {
            val parser = SseParser()
            parser.consume("event: one")
            parser.consume("data: 1")
            val first = parser.consume("")
            parser.consume("data: 2")
            val second = parser.consume("")
            assertEquals("one", first?.name)
            assertNull(second?.name) // name must not carry over
            assertEquals("2", second?.data)
        }

        @Test
        fun `okio line reading preserves the blank lines that delimit SSE events`() {
            // iOS shipped a silent-no-reply bug because URLSession's line
            // convenience swallows blank lines. Pin the OkHttp/Okio behavior
            // this port depends on: readUtf8Line() must yield empties.
            val buffer = Buffer().writeUtf8("event: message_stop\r\ndata: {}\r\n\r\n")
            val lines = mutableListOf<String>()
            while (true) {
                lines += buffer.readUtf8Line() ?: break
            }
            assertEquals(listOf("event: message_stop", "data: {}", ""), lines)
        }
    }

    @Nested
    @Tag("parsing")
    inner class Payloads {

        @Test
        fun `unknown event types are tolerated - new API events must not break old clients`() {
            assertEquals(AnthropicStreamPayload.Ignored, AnthropicStreamPayload.decode("""{"type": "brand_new_event"}"""))
        }

        @Test
        fun `undecodable payloads surface as errors, never crash`() {
            assertInstanceOf(AnthropicStreamPayload.ApiError::class.java, AnthropicStreamPayload.decode("not json"))
        }

        @Test
        fun `tool-use start and input deltas decode with their indices`() {
            assertEquals(
                AnthropicStreamPayload.ContentBlockStartToolUse(1, "tu_9", "book_appointment"),
                AnthropicStreamPayload.decode(
                    """{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_9","name":"book_appointment","input":{}}}"""
                ),
            )
            assertEquals(
                AnthropicStreamPayload.InputJsonDelta(1, """{"day""""),
                AnthropicStreamPayload.decode(
                    """{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"day\""}}"""
                ),
            )
        }

        @Test
        fun `input deltas for an unknown block index are dropped, not crashed on`() {
            val toolIds = mutableMapOf<Int, String>()
            val events = ClaudeProvider.map(AnthropicStreamPayload.InputJsonDelta(7, "{}"), toolIds)
            assertTrue(events.isEmpty())
        }
    }

    @Nested
    @Tag("agent")
    inner class Turns {

        @Test
        fun `tool input split across deltas reassembles into valid JSON`() {
            var call = TurnAccumulator.ToolCall("tu_1", "book_appointment", "")
            call = call.copy(inputJson = call.inputJson + """{"customer_name": "Da""")
            call = call.copy(inputJson = call.inputJson + """na Reyes", "service": "tune-up", "day": "Thursday"}""")
            val input = call.decodedInput()
            assertEquals("Dana Reyes", input["customer_name"]?.jsonPrimitive?.contentOrNull)
            assertEquals("Thursday", input["day"]?.jsonPrimitive?.contentOrNull)
        }

        @Test
        fun `empty tool input decodes as an empty object, not a decode failure`() {
            assertTrue(TurnAccumulator.ToolCall("tu_1", "mark_lead_handled", "").decodedInput().isEmpty())
        }

        @Test
        fun `assistant blocks keep model order - text first, then tool calls`() {
            val turn = TurnAccumulator()
            turn.text = "Let me check."
            turn.toolCalls += TurnAccumulator.ToolCall("tu_1", "lookup_customer", """{"name":"Dana"}""")
            val blocks = turn.assistantBlocks()
            assertEquals(2, blocks.size)
            assertInstanceOf(WireContentBlock.Text::class.java, blocks[0])
            assertInstanceOf(WireContentBlock.ToolUse::class.java, blocks[1])
        }
    }

    @Nested
    @Tag("persistence")
    inner class Outbox {

        @Test
        fun `snapshots round-trip through disk`() {
            val outbox = AgentOutbox(temporaryOutboxDirectory())
            val snapshot = AgentOutbox.SessionSnapshot(
                conversation = listOf(WireMessage.user("hello")),
                transcript = listOf(ChatMessage(kind = ChatMessage.Kind.CUSTOMER, text = "hello")),
                interrupted = true,
            )
            outbox.save(snapshot, "lead-1")
            assertEquals(snapshot, outbox.load("lead-1"))
            outbox.clear("lead-1")
            assertNull(outbox.load("lead-1"))
        }

        @Test
        fun `an interrupted session restores as resumable and replays a user-terminated conversation`() = runTest {
            val lead = Lead.sample
            val directory = temporaryOutboxDirectory()

            // Simulate an app death mid-run: conversation saved, interrupted.
            AgentOutbox(directory).save(
                AgentOutbox.SessionSnapshot(
                    conversation = listOf(WireMessage.user("New SMS lead from Dana Reyes: \"help\"")),
                    transcript = listOf(ChatMessage(kind = ChatMessage.Kind.CUSTOMER, text = "help")),
                    interrupted = true,
                ),
                lead.id,
            )

            val provider = FakeModelProvider(listOf(ScriptedTurn.textTurn("Picking this back up!")))
            val engine = AgentEngine(lead, provider, CrmStore(listOf(lead)), AgentOutbox(directory), this)

            assertTrue(engine.canResume.value)
            engine.resume()
            advanceUntilIdle()

            // The replayed request is the saved conversation, ending on the user turn.
            assertEquals("user", provider.recordedRequests.first().last().role)
            assertEquals(AgentState.Idle, engine.state.value)
            assertFalse(engine.canResume.value)
            assertEquals(2, engine.transcript.value.size)
        }
    }

    @Nested
    @Tag("agent")
    inner class FailurePaths {

        @Test
        fun `a connectivity failure surfaces as the offline category and retry replays the run`() = runTest {
            val provider = FakeModelProvider(
                listOf(
                    ScriptedTurn.Failure(UnknownHostException("api.anthropic.com")),
                    ScriptedTurn.textTurn("Back online — happy to help!"),
                )
            )
            val (engine, _, _) = makeEngine(this, provider)

            engine.startIfNeeded()
            advanceUntilIdle()
            assertEquals(AgentState.Failed(AgentError.OFFLINE), engine.state.value)

            engine.retry()
            advanceUntilIdle()
            assertEquals(AgentState.Idle, engine.state.value)
            assertEquals("Back online — happy to help!", engine.transcript.value.last().text)
        }

        @Test
        fun `cancel mid-stream leaves the session idle and resumable - never a spinner`() = runTest {
            val provider = FakeModelProvider(listOf(ScriptedTurn.Hang))
            val (engine, _, outbox) = makeEngine(this, provider)

            engine.startIfNeeded()
            runCurrent()
            assertEquals(AgentState.Thinking, engine.state.value)

            engine.cancel()
            advanceUntilIdle()
            assertEquals(AgentState.Idle, engine.state.value)
            assertTrue(engine.canResume.value)
            assertEquals(true, outbox.load(engine.lead.id)?.interrupted)
        }

        @Test
        fun `a stream that completes with zero events fails loudly - never a silent idle`() = runTest {
            val provider = FakeModelProvider(listOf(ScriptedTurn.Events(emptyList())))
            val (engine, _, _) = makeEngine(this, provider)

            engine.startIfNeeded()
            advanceUntilIdle()
            assertEquals(AgentState.Failed(AgentError.SERVER), engine.state.value)
        }
    }
}
