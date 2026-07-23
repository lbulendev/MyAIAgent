package com.curiousbeagle.android.myaiagent.net

import com.curiousbeagle.android.myaiagent.model.AgentError
import com.curiousbeagle.android.myaiagent.model.AgentFailure
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.serialization.encodeToString
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * Streams the Anthropic Messages API over SSE and maps wire payloads to
 * provider-neutral [StreamEvent]s. Mirrors iOS `ClaudeProvider`. The API key
 * arrives via local.properties/env -> BuildConfig; it is never hardcoded.
 */
class ClaudeProvider(private val apiKey: String) : ModelProvider {

    companion object {
        const val MODEL = "claude-opus-4-8"
        const val MAX_TOKENS = 4096 // short conversational turns; keeps demo cost bounded
        private const val ENDPOINT = "https://api.anthropic.com/v1/messages"

        /**
         * Wire payload -> provider-neutral events. Pure (given the index
         * map) so the regression suite can pin the mapping — mirrors
         * `ClaudeProvider.map` on iOS.
         */
        fun map(
            payload: AnthropicStreamPayload,
            toolIdsByIndex: MutableMap<Int, String>,
        ): List<StreamEvent> = when (payload) {
            is AnthropicStreamPayload.ContentBlockStartText -> listOf(StreamEvent.TextStarted)
            is AnthropicStreamPayload.ContentBlockStartToolUse -> {
                toolIdsByIndex[payload.index] = payload.id
                listOf(StreamEvent.ToolUseStarted(payload.id, payload.name))
            }
            is AnthropicStreamPayload.TextDelta -> listOf(StreamEvent.TextDelta(payload.text))
            is AnthropicStreamPayload.InputJsonDelta ->
                toolIdsByIndex[payload.index]
                    ?.let { listOf(StreamEvent.ToolInputDelta(it, payload.partialJson)) }
                    ?: emptyList()
            is AnthropicStreamPayload.ContentBlockStop ->
                toolIdsByIndex.remove(payload.index)
                    ?.let { listOf(StreamEvent.ToolUseFinished(it)) }
                    ?: emptyList()
            is AnthropicStreamPayload.MessageDelta -> when (payload.stopReason) {
                null -> emptyList()
                "end_turn" -> listOf(StreamEvent.Finished(StreamEvent.StopReason.EndTurn))
                "tool_use" -> listOf(StreamEvent.Finished(StreamEvent.StopReason.ToolUse))
                "max_tokens" -> listOf(StreamEvent.Finished(StreamEvent.StopReason.MaxTokens))
                else -> listOf(StreamEvent.Finished(StreamEvent.StopReason.Other(payload.stopReason)))
            }
            AnthropicStreamPayload.MessageStop,
            AnthropicStreamPayload.Ignored,
            is AnthropicStreamPayload.ApiError -> emptyList()
        }
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS) // SSE: the stream stays open between events
        .build()

    override fun stream(
        system: String,
        tools: List<ToolDefinition>,
        messages: List<WireMessage>,
    ): Flow<StreamEvent> = flow {
        val body = wireJson.encodeToString(
            MessagesRequest(MODEL, MAX_TOKENS, system, tools, messages, stream = true)
        )
        val request = Request.Builder()
            .url(ENDPOINT)
            .header("Content-Type", "application/json")
            .header("x-api-key", apiKey)
            .header("anthropic-version", "2023-06-01")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw AgentFailure(if (response.code >= 500) AgentError.SERVER else AgentError.GENERIC)
            }
            val source = response.body?.source() ?: throw AgentFailure(AgentError.SERVER)

            // readUtf8Line() preserves empty lines — the SSE event delimiter.
            // (URLSession's line convenience on iOS swallowed them; the
            // regression suite pins the parser's dependence on empties.)
            val parser = SseParser()
            val toolIdsByIndex = mutableMapOf<Int, String>()
            while (true) {
                val line = source.readUtf8Line() ?: break
                val event = parser.consume(line) ?: continue
                val payload = AnthropicStreamPayload.decode(event.data)
                if (payload is AnthropicStreamPayload.ApiError) throw AgentFailure(AgentError.SERVER)
                map(payload, toolIdsByIndex).forEach { emit(it) }
            }
            // Flush any event pending at EOF (stream ended without a final blank line).
            parser.consume("")?.let { event ->
                val payload = AnthropicStreamPayload.decode(event.data)
                if (payload is AnthropicStreamPayload.ApiError) throw AgentFailure(AgentError.SERVER)
                map(payload, toolIdsByIndex).forEach { emit(it) }
            }
        }
    }.flowOn(Dispatchers.IO)
}
