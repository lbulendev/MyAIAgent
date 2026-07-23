//
//  CRMStore.swift
//  MyAIAgent
//

import Foundation
import Observation

/// Mock CRM the agent's tools act on — customers, appointments, and the lead
/// queue. In-memory by design: the demo is about the agent orchestrating
/// tools, not about persistence. Lives on the main actor because tool results
/// mutate UI-visible state.
@Observable
final class CRMStore {
    nonisolated struct Customer: Identifiable, Equatable {
        let id: UUID
        var name: String
        var phone: String
        var bike: String
        var lastVisit: String
    }

    nonisolated struct Appointment: Identifiable, Equatable {
        let id: String
        var customerName: String
        var service: String
        var day: String
    }

    /// A simulated text-to-pay link (the Podium-style "conversations into
    /// revenue" step). Nothing real is charged — the demo stops at "sent".
    nonisolated struct PaymentLink: Identifiable, Equatable {
        let id: String
        var customerName: String
        var amountUSD: Int
        var memo: String
        var url: String { "https://pay.beaglebike.shop/\(id)" }
    }

    private(set) var customers: [Customer]
    private(set) var appointments: [Appointment] = []
    private(set) var paymentLinks: [PaymentLink] = []
    var leads: [Lead]

    private var nextAppointmentNumber = 1042
    private var nextPaymentLinkNumber = 5001

    init(leads: [Lead] = Lead.samples) {
        self.leads = leads
        self.customers = [
            Customer(id: UUID(), name: "Dana Reyes", phone: "555-0117", bike: "Trek FX 3", lastVisit: "March 2026"),
            Customer(id: UUID(), name: "Priya Natarajan", phone: "555-0198", bike: "Specialized Sirrus", lastVisit: "June 2026"),
        ]
    }

    // MARK: Tool operations

    /// Case-insensitive lookup; returns nil when the customer is unknown.
    func lookupCustomer(named name: String) -> Customer? {
        customers.first { $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name) }
    }

    /// Books an appointment and returns its confirmation id.
    func bookAppointment(customerName: String, service: String, day: String) -> Appointment {
        let appointment = Appointment(
            id: "A-\(nextAppointmentNumber)",
            customerName: customerName,
            service: service,
            day: day
        )
        nextAppointmentNumber += 1
        appointments.append(appointment)
        return appointment
    }

    /// Creates a simulated payment link the agent can "text" the customer.
    func sendPaymentLink(customerName: String, amountUSD: Int, memo: String) -> PaymentLink {
        let link = PaymentLink(
            id: "PL-\(nextPaymentLinkNumber)",
            customerName: customerName,
            amountUSD: amountUSD,
            memo: memo
        )
        nextPaymentLinkNumber += 1
        paymentLinks.append(link)
        return link
    }

    /// Marks a lead handled so it drops out of the active queue.
    func markLeadHandled(id: UUID) {
        guard let index = leads.firstIndex(where: { $0.id == id }) else { return }
        leads[index].status = .handled
    }

    func markLeadInProgress(id: UUID) {
        guard let index = leads.firstIndex(where: { $0.id == id }) else { return }
        if leads[index].status == .new { leads[index].status = .inProgress }
    }
}
