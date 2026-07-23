//
//  ToolRegistry.swift
//  MyAIAgent
//

import Foundation

/// The client-side tools the AI worker can call, and their dispatch against
/// the CRM. Definitions are wire-format JSON Schema; execution runs on the
/// main actor because tool results mutate UI-visible CRM state.
enum ToolRegistry {
    nonisolated static let definitions: [ToolDefinition] = [
        ToolDefinition(
            name: "lookup_customer",
            description: "Look up an existing customer record by name. Call this before booking anything so you know whether the customer is already in the system.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("The customer's name as given in the conversation"),
                    ]),
                ]),
                "required": .array([.string("name")]),
            ])
        ),
        ToolDefinition(
            name: "book_appointment",
            description: "Book a service appointment. Call this when the customer has agreed on a service and a day.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "customer_name": .object(["type": .string("string")]),
                    "service": .object([
                        "type": .string("string"),
                        "description": .string("Short service description, e.g. 'derailleur tune-up'"),
                    ]),
                    "day": .object([
                        "type": .string("string"),
                        "description": .string("Requested day, e.g. 'Thursday'"),
                    ]),
                ]),
                "required": .array([.string("customer_name"), .string("service"), .string("day")]),
            ])
        ),
        ToolDefinition(
            name: "send_payment_link",
            description: "Text the customer a secure payment link to collect a deposit or payment. Call this after booking a service appointment to collect the shop's standard $20 deposit. This simulates sending; do not ask the customer for card details.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "customer_name": .object(["type": .string("string")]),
                    "amount_usd": .object([
                        "type": .string("integer"),
                        "description": .string("Whole-dollar amount, e.g. 20 for the standard deposit"),
                    ]),
                    "memo": .object([
                        "type": .string("string"),
                        "description": .string("What the payment is for, e.g. 'tune-up deposit'"),
                    ]),
                ]),
                "required": .array([.string("customer_name"), .string("amount_usd"), .string("memo")]),
            ])
        ),
        ToolDefinition(
            name: "mark_lead_handled",
            description: "Mark the current lead as handled once the customer's request is fully resolved. Call this exactly once, at the end.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "summary": .object([
                        "type": .string("string"),
                        "description": .string("One sentence describing how the lead was resolved"),
                    ]),
                ]),
                "required": .array([.string("summary")]),
            ])
        ),
    ]

    /// Executes a tool call and returns (result text for the model,
    /// activity note for the transcript). Unknown tools and bad inputs
    /// return error results the model can recover from — they never throw.
    static func execute(
        name: String,
        input: JSONValue,
        store: CRMStore,
        leadID: UUID
    ) -> (result: String, isError: Bool, activity: String) {
        switch name {
        case "lookup_customer":
            guard let customerName = input["name"]?.stringValue else {
                return ("Missing required field: name", true, "Customer lookup failed")
            }
            if let customer = store.lookupCustomer(named: customerName) {
                return (
                    "Found customer: \(customer.name), phone \(customer.phone), bike \(customer.bike), last visit \(customer.lastVisit).",
                    false,
                    "Looked up \(customer.name)"
                )
            }
            return ("No customer record found for \(customerName).", false, "No record for \(customerName)")

        case "book_appointment":
            guard let customerName = input["customer_name"]?.stringValue,
                  let service = input["service"]?.stringValue,
                  let day = input["day"]?.stringValue else {
                return ("Missing required fields: customer_name, service, day", true, "Booking failed")
            }
            let appointment = store.bookAppointment(customerName: customerName, service: service, day: day)
            return (
                "Booked appointment \(appointment.id): \(service) for \(customerName) on \(day).",
                false,
                "Booked \(appointment.id) — \(service), \(day)"
            )

        case "send_payment_link":
            guard let customerName = input["customer_name"]?.stringValue,
                  let amountUSD = input["amount_usd"]?.intValue,
                  let memo = input["memo"]?.stringValue else {
                return ("Missing required fields: customer_name, amount_usd, memo", true, "Payment link failed")
            }
            let link = store.sendPaymentLink(customerName: customerName, amountUSD: amountUSD, memo: memo)
            return (
                "Sent payment link \(link.id) (\(link.url)) to \(customerName) for $\(amountUSD) — \(memo). Simulated: no real charge.",
                false,
                "Sent $\(amountUSD) payment link \(link.id)"
            )

        case "mark_lead_handled":
            let summary = input["summary"]?.stringValue ?? ""
            store.markLeadHandled(id: leadID)
            return ("Lead marked handled.", false, "Lead handled: \(summary)")

        default:
            return ("Unknown tool: \(name)", true, "Unknown tool \(name)")
        }
    }
}
