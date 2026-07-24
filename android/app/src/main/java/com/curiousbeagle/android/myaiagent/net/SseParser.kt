package com.curiousbeagle.android.myaiagent.net

/**
 * Incremental Server-Sent Events parser, mirroring iOS `SSEParser`. Feed it
 * lines (INCLUDING empty ones — blank lines are the event delimiter); it
 * emits complete events. Pure and synchronous so the regression suite can
 * pin edge cases without networking.
 *
 * The iOS side learned this the hard way: a line source that swallows blank
 * lines (URLSession's `bytes.lines`) starves this parser and every stream
 * completes silently empty. OkHttp's `BufferedSource.readUtf8Line()`
 * preserves empties — the regression suite pins that assumption.
 */
class SseParser {
    data class Event(val name: String?, val data: String)

    private var currentName: String? = null
    private val currentData = mutableListOf<String>()

    /**
     * Consume one line (without its terminator). Returns a completed event
     * when the line is the blank separator, null otherwise.
     */
    fun consume(line: String): Event? {
        if (line.isEmpty()) {
            val event = if (currentData.isEmpty()) {
                null
            } else {
                Event(currentName, currentData.joinToString("\n"))
            }
            currentName = null
            currentData.clear()
            return event
        }
        if (line.startsWith(":")) return null // comment / keep-alive

        val parts = line.split(":", limit = 2)
        val field = parts.first()
        val value = parts.last().trim()

        when (field) {
            "event" -> currentName = value
            "data" -> currentData += value
            // id, retry, unknown fields — not used
        }
        return null
    }
}
