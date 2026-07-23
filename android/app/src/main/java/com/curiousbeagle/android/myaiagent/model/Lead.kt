package com.curiousbeagle.android.myaiagent.model

import kotlinx.serialization.Serializable

/** An inbound customer inquiry the AI worker can handle. Mirrors iOS `Lead`. */
@Serializable
data class Lead(
    val id: String,
    val customerName: String,
    val channel: String,
    val message: String,
    val status: Status = Status.NEW,
) {
    enum class Status { NEW, IN_PROGRESS, HANDLED }

    companion object {
        val sample = Lead(
            id = "lead-dana",
            customerName = "Dana Reyes",
            channel = "SMS",
            message = "Hi — my rear derailleur is skipping gears. Can I get a tune-up this week?",
        )

        val samples = listOf(
            sample,
            Lead(
                id = "lead-marcus",
                customerName = "Marcus Webb",
                channel = "Web form",
                message = "Do you sell kids' helmets? Looking for something for a 7-year-old.",
            ),
            Lead(
                id = "lead-priya",
                customerName = "Priya Natarajan",
                channel = "SMS",
                message = "Flat tire on my commuter bike. How soon could you fit me in for a repair?",
            ),
        )
    }
}
