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
        @Test("The registry exposes the five worker tools with unique names")
        func registryShape() {
            let names = ToolRegistry.definitions.map(\.name)
            #expect(names == ["lookup_customer", "find_help_article", "book_appointment", "send_payment_link", "mark_lead_handled"])
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

    @Suite("Help catalog", .tags(.catalog))
    struct HelpCatalogContract {
        @Test("The bundled catalog ships both kinds, and the offline badge stays honest: at least one online-only entry exists")
        func bundledContract() {
            let catalog = HelpCatalog.bundled
            #expect(!catalog.articles.isEmpty)
            #expect(!catalog.services.isEmpty)
            #expect(catalog.entries.contains { $0.requirement == .online })
            for article in catalog.articles {
                #expect(!article.steps.isEmpty, "\(article.id) has no steps")
                #expect(article.requirement == .none, "\(article.id): bundled articles must work offline")
            }
        }

        @Test("Keyword scoring is case-insensitive and ranks the right guide first")
        func scoring() {
            let catalog = HelpCatalog.bundled
            #expect(catalog.matches(for: "FLAT TIRE").first?.id == "fix-flat")
            #expect(catalog.matches(for: "my gears keep skipping").first?.id == "chain-care")
            #expect(catalog.matches(for: "xylophone lessons").isEmpty)
            #expect(catalog.matches(for: "").isEmpty)
        }

        @Test("Availability follows the requirement and current connectivity")
        func availability() throws {
            let catalog = HelpCatalog.bundled
            let article = try #require(catalog.articles.first)
            let onlineOnly = try #require(catalog.entries.first { $0.requirement == .online })
            #expect(article.isAvailable(online: false))
            #expect(article.isAvailable(online: true))
            #expect(onlineOnly.isAvailable(online: true))
            #expect(!onlineOnly.isAvailable(online: false))
        }

        @Test("Offline suggestions only ever offer offline-capable articles, capped at the limit")
        func offlineSuggestions() {
            let suggestions = HelpCatalog.bundled.offlineSuggestions(for: Lead.samples[2].message)
            #expect(suggestions.first?.id == "fix-flat")
            #expect(suggestions.count <= 2)
            #expect(suggestions.allSatisfy { $0.kind == .helpArticle && $0.requirement == .none })
        }
    }

    @Suite("Help tool", .tags(.tools))
    @MainActor
    struct HelpTool {
        @Test("find_help_article returns the numbered shop-approved steps")
        func happyPath() {
            let outcome = ToolRegistry.execute(
                name: "find_help_article",
                input: .object(["topic": .string("flat tire")]),
                store: CRMStore(),
                leadID: Lead.sample.id
            )
            #expect(!outcome.isError)
            #expect(outcome.result.contains("Guide: Fix a flat tire"))
            #expect(outcome.result.contains("1. "))
            #expect(outcome.result.contains("offline"))
            #expect(outcome.activity == "Shared guide: Fix a flat tire")
        }

        @Test("No matching guide is a normal result the model can work with — not an error")
        func noMatch() {
            let outcome = ToolRegistry.execute(
                name: "find_help_article",
                input: .object(["topic": .string("submarine repair")]),
                store: CRMStore(),
                leadID: Lead.sample.id
            )
            #expect(!outcome.isError)
            #expect(outcome.result.contains("No self-help guide"))
        }

        @Test("A missing topic is an error result, never a dropped call")
        func missingTopic() {
            let outcome = ToolRegistry.execute(
                name: "find_help_article",
                input: .object([:]),
                store: CRMStore(),
                leadID: Lead.sample.id
            )
            #expect(outcome.isError)
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
