package com.curiousbeagle.android.myaiagent.agent

import com.curiousbeagle.android.myaiagent.model.CrmStore
import com.curiousbeagle.android.myaiagent.net.ToolDefinition
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/**
 * The client-side tools the AI worker can call, and their dispatch against
 * the CRM. Mirrors iOS `ToolRegistry` — definitions are wire-format JSON
 * Schema; execution never throws (unknown tools and bad inputs return
 * error results the model can recover from).
 */
object ToolRegistry {

    data class Outcome(val result: String, val isError: Boolean, val activity: String)

    val definitions: List<ToolDefinition> = listOf(
        ToolDefinition(
            name = "lookup_customer",
            description = "Look up an existing customer record by name. Call this before booking anything so you know whether the customer is already in the system.",
            inputSchema = buildJsonObject {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("name") {
                        put("type", "string")
                        put("description", "The customer's name as given in the conversation")
                    }
                }
                putJsonArray("required") { add(JsonPrimitive("name")) }
            },
        ),
        ToolDefinition(
            name = "book_appointment",
            description = "Book a service appointment. Call this when the customer has agreed on a service and a day.",
            inputSchema = buildJsonObject {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("customer_name") { put("type", "string") }
                    putJsonObject("service") {
                        put("type", "string")
                        put("description", "Short service description, e.g. 'derailleur tune-up'")
                    }
                    putJsonObject("day") {
                        put("type", "string")
                        put("description", "Requested day, e.g. 'Thursday'")
                    }
                }
                putJsonArray("required") {
                    add(JsonPrimitive("customer_name"))
                    add(JsonPrimitive("service"))
                    add(JsonPrimitive("day"))
                }
            },
        ),
        ToolDefinition(
            name = "send_payment_link",
            description = "Text the customer a secure payment link to collect a deposit or payment. Call this after booking a service appointment to collect the shop's standard $20 deposit. This simulates sending; do not ask the customer for card details.",
            inputSchema = buildJsonObject {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("customer_name") { put("type", "string") }
                    putJsonObject("amount_usd") {
                        put("type", "integer")
                        put("description", "Whole-dollar amount, e.g. 20 for the standard deposit")
                    }
                    putJsonObject("memo") {
                        put("type", "string")
                        put("description", "What the payment is for, e.g. 'tune-up deposit'")
                    }
                }
                putJsonArray("required") {
                    add(JsonPrimitive("customer_name"))
                    add(JsonPrimitive("amount_usd"))
                    add(JsonPrimitive("memo"))
                }
            },
        ),
        ToolDefinition(
            name = "mark_lead_handled",
            description = "Mark the current lead as handled once the customer's request is fully resolved. Call this exactly once, at the end.",
            inputSchema = buildJsonObject {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("summary") {
                        put("type", "string")
                        put("description", "One sentence describing how the lead was resolved")
                    }
                }
                putJsonArray("required") { add(JsonPrimitive("summary")) }
            },
        ),
    )

    fun execute(name: String, input: JsonObject, store: CrmStore, leadId: String): Outcome = when (name) {
        "lookup_customer" -> {
            val customerName = input.string("name")
            if (customerName == null) {
                Outcome("Missing required field: name", isError = true, activity = "Customer lookup failed")
            } else {
                val customer = store.lookupCustomer(customerName)
                if (customer != null) {
                    Outcome(
                        "Found customer: ${customer.name}, phone ${customer.phone}, bike ${customer.bike}, last visit ${customer.lastVisit}.",
                        isError = false,
                        activity = "Looked up ${customer.name}",
                    )
                } else {
                    Outcome("No customer record found for $customerName.", isError = false, activity = "No record for $customerName")
                }
            }
        }

        "book_appointment" -> {
            val customerName = input.string("customer_name")
            val service = input.string("service")
            val day = input.string("day")
            if (customerName == null || service == null || day == null) {
                Outcome("Missing required fields: customer_name, service, day", isError = true, activity = "Booking failed")
            } else {
                val appointment = store.bookAppointment(customerName, service, day)
                Outcome(
                    "Booked appointment ${appointment.id}: $service for $customerName on $day.",
                    isError = false,
                    activity = "Booked ${appointment.id} — $service, $day",
                )
            }
        }

        "send_payment_link" -> {
            val customerName = input.string("customer_name")
            val amountUsd = input.int("amount_usd")
            val memo = input.string("memo")
            if (customerName == null || amountUsd == null || memo == null) {
                Outcome("Missing required fields: customer_name, amount_usd, memo", isError = true, activity = "Payment link failed")
            } else {
                val link = store.sendPaymentLink(customerName, amountUsd, memo)
                Outcome(
                    "Sent payment link ${link.id} (${link.url}) to $customerName for $$amountUsd — $memo. Simulated: no real charge.",
                    isError = false,
                    activity = "Sent $$amountUsd payment link ${link.id}",
                )
            }
        }

        "mark_lead_handled" -> {
            val summary = input.string("summary").orEmpty()
            store.markLeadHandled(leadId)
            Outcome("Lead marked handled.", isError = false, activity = "Lead handled: $summary")
        }

        else -> Outcome("Unknown tool: $name", isError = true, activity = "Unknown tool $name")
    }

    private fun JsonObject.string(key: String): String? =
        (this[key] as? JsonPrimitive)?.contentOrNull

    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.intOrNull
}
