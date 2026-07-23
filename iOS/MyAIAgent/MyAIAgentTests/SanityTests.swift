//
//  SanityTests.swift
//  MyAIAgentTests
//

import Foundation
import Testing
@testable import MyAIAgent

// Contract checks on scaffolding: tool schemas, CRM behavior, error
// mapping, and the system prompt. Failures usually mean drift, not bugs.
@Suite("Sanity", .tags(.sanity))
struct SanityTests {

    @Suite("Tool definitions", .tags(.tools))
    struct ToolDefinitions {
        @Test("The registry exposes the four worker tools with unique names")
        func registryShape() {
            let names = ToolRegistry.definitions.map(\.name)
            #expect(names == ["lookup_customer", "book_appointment", "send_payment_link", "mark_lead_handled"])
            #expect(Set(names).count == names.count)
        }

        @Test("Every tool schema is an object with a required array")
        func schemasAreObjects() throws {
            for definition in ToolRegistry.definitions {
                #expect(definition.inputSchema["type"]?.stringValue == "object", "\(definition.name)")
                let required = definition.inputSchema["required"]
                #expect(required != nil, "\(definition.name) has no required fields")
            }
        }
    }

    @Suite("CRM", .tags(.tools))
    @MainActor
    struct CRM {
        @Test("Customer lookup is case-insensitive and partial-tolerant")
        func lookup() {
            let store = CRMStore()
            #expect(store.lookupCustomer(named: "dana reyes") != nil)
            #expect(store.lookupCustomer(named: "Dana") != nil)
            #expect(store.lookupCustomer(named: "Nobody Realman") == nil)
        }

        @Test("Booked appointments get sequential confirmation ids")
        func booking() {
            let store = CRMStore()
            let first = store.bookAppointment(customerName: "A", service: "tune-up", day: "Thursday")
            let second = store.bookAppointment(customerName: "B", service: "flat fix", day: "Friday")
            #expect(first.id == "A-1042")
            #expect(second.id == "A-1043")
            #expect(store.appointments.count == 2)
        }

        @Test("Payment links get sequential ids and record the simulated send")
        func paymentLinks() {
            let store = CRMStore()
            let link = store.sendPaymentLink(customerName: "Dana Reyes", amountUSD: 20, memo: "tune-up deposit")
            #expect(link.id == "PL-5001")
            #expect(link.url == "https://pay.beaglebike.shop/PL-5001")
            #expect(store.sendPaymentLink(customerName: "B", amountUSD: 35, memo: "helmet").id == "PL-5002")
            #expect(store.paymentLinks.count == 2)
        }

        @Test("The payment tool simulates a text-to-pay send — never card entry")
        func paymentToolExecution() {
            let store = CRMStore()
            let outcome = ToolRegistry.execute(
                name: "send_payment_link",
                input: .object([
                    "customer_name": .string("Dana Reyes"),
                    "amount_usd": .number(20),
                    "memo": .string("tune-up deposit"),
                ]),
                store: store,
                leadID: Lead.sample.id
            )
            #expect(!outcome.isError)
            #expect(outcome.result.contains("PL-5001"))
            #expect(outcome.result.contains("Simulated"))
            #expect(outcome.activity == "Sent $20 payment link PL-5001")
        }

        @Test("Marking a lead handled updates its status")
        func leadStatus() {
            let lead = Lead.sample
            let store = CRMStore(leads: [lead])
            store.markLeadHandled(id: lead.id)
            #expect(store.leads.first?.status == .handled)
        }
    }

    @Suite("Error mapping", .tags(.agent))
    struct ErrorMapping {
        @Test("Connectivity failures map to the offline category")
        func offline() {
            #expect(AgentError.categorize(URLError(.notConnectedToInternet)) == .offline)
            #expect(AgentError.categorize(URLError(.networkConnectionLost)) == .offline)
            #expect(AgentError.categorize(URLError(.timedOut)) == .offline)
        }

        @Test("Other errors fall through to server or generic — never raw text")
        func fallthroughCategories() {
            #expect(AgentError.categorize(URLError(.badServerResponse)) == .generic)
            #expect(AgentError.categorize(AgentError.server) == .server)
            struct Mystery: Error {}
            #expect(AgentError.categorize(Mystery()) == .generic)
        }
    }

    @Suite("Prompt", .tags(.agent))
    struct Prompt {
        @Test("The system prompt names the lead and pins the tool rules")
        func promptContents() {
            let prompt = AgentEngine.systemPrompt(for: .sample)
            #expect(prompt.contains("Dana Reyes"))
            #expect(prompt.contains("lookup_customer"))
            #expect(prompt.contains("mark_lead_handled"))
        }
    }
}
