package com.curiousbeagle.android.myaiagent.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

/**
 * Wire types for the Anthropic Messages API, mirroring iOS `AnthropicWire`.
 * kotlinx.serialization's sealed-class discriminator produces the exact
 * `"type"` values the API expects; dynamic shapes (tool inputs, schemas)
 * stay as [JsonObject].
 */

val wireJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = false
    classDiscriminator = "type"
}

@Serializable
data class ToolDefinition(
    val name: String,
    val description: String,
    @SerialName("input_schema") val inputSchema: JsonObject,
)

@Serializable
sealed class WireContentBlock {
    @Serializable
    @SerialName("text")
    data class Text(val text: String) : WireContentBlock()

    @Serializable
    @SerialName("tool_use")
    data class ToolUse(val id: String, val name: String, val input: JsonObject) : WireContentBlock()

    @Serializable
    @SerialName("tool_result")
    data class ToolResult(
        @SerialName("tool_use_id") val toolUseId: String,
        val content: String,
        @SerialName("is_error") val isError: Boolean = false,
    ) : WireContentBlock()
}

@Serializable
data class WireMessage(val role: String, val content: List<WireContentBlock>) {
    companion object {
        fun user(text: String) = WireMessage("user", listOf(WireContentBlock.Text(text)))
    }
}

@Serializable
data class MessagesRequest(
    val model: String,
    @SerialName("max_tokens") val maxTokens: Int,
    val system: String,
    val tools: List<ToolDefinition>,
    val messages: List<WireMessage>,
    val stream: Boolean,
)

/**
 * Raw stream payloads decoded from SSE `data:` JSON by its `type`
 * discriminator. Tolerant on purpose: unknown event types are [Ignored],
 * not an error — the API adds event types over time and old clients must
 * not break. Mirrors iOS `AnthropicStreamPayload`.
 */
sealed interface AnthropicStreamPayload {
    data class ContentBlockStartText(val index: Int) : AnthropicStreamPayload
    data class ContentBlockStartToolUse(val index: Int, val id: String, val name: String) : AnthropicStreamPayload
    data class TextDelta(val index: Int, val text: String) : AnthropicStreamPayload
    data class InputJsonDelta(val index: Int, val partialJson: String) : AnthropicStreamPayload
    data class ContentBlockStop(val index: Int) : AnthropicStreamPayload
    data class MessageDelta(val stopReason: String?) : AnthropicStreamPayload
    data object MessageStop : AnthropicStreamPayload
    data object Ignored : AnthropicStreamPayload
    data class ApiError(val message: String) : AnthropicStreamPayload

    companion object {
        // Non-throwing accessors: a malformed shape yields null, never an exception.
        private fun JsonElement?.obj(): JsonObject? = this as? JsonObject
        private fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.contentOrNull
        private fun JsonElement?.int(): Int? = (this as? JsonPrimitive)?.intOrNull

        fun decode(data: String): AnthropicStreamPayload {
            val json = runCatching { wireJson.parseToJsonElement(data) }.getOrNull().obj()
                ?: return ApiError("undecodable stream payload")
            return when (json["type"].str() ?: return ApiError("undecodable stream payload")) {
                "content_block_start" -> {
                    val index = json["index"].int() ?: return Ignored
                    val block = json["content_block"].obj() ?: return Ignored
                    when (block["type"].str()) {
                        "text" -> ContentBlockStartText(index)
                        "tool_use" -> {
                            val id = block["id"].str() ?: return Ignored
                            val name = block["name"].str() ?: return Ignored
                            ContentBlockStartToolUse(index, id, name)
                        }
                        else -> Ignored
                    }
                }
                "content_block_delta" -> {
                    val index = json["index"].int() ?: return Ignored
                    val delta = json["delta"].obj() ?: return Ignored
                    when (delta["type"].str()) {
                        "text_delta" -> delta["text"].str()?.let { TextDelta(index, it) } ?: Ignored
                        "input_json_delta" -> delta["partial_json"].str()?.let { InputJsonDelta(index, it) } ?: Ignored
                        else -> Ignored
                    }
                }
                "content_block_stop" -> json["index"].int()?.let { ContentBlockStop(it) } ?: Ignored
                "message_delta" -> MessageDelta(json["delta"].obj()?.get("stop_reason").str())
                "message_stop" -> MessageStop
                "error" -> ApiError(json["error"].obj()?.get("message").str() ?: "stream error")
                else -> Ignored
            }
        }
    }
}
