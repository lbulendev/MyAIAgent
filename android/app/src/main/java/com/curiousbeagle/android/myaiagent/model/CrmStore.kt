package com.curiousbeagle.android.myaiagent.model

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Mock CRM the agent's tools act on — customers, appointments, and the lead
 * queue. In-memory by design: the demo is about the agent orchestrating
 * tools, not persistence. StateFlow-backed so Compose observes mutations
 * (the `@Observable` analog). Mirrors iOS `CRMStore`.
 */
class CrmStore(initialLeads: List<Lead> = Lead.samples) {

    data class Customer(
        val name: String,
        val phone: String,
        val bike: String,
        val lastVisit: String,
    )

    data class Appointment(
        val id: String,
        val customerName: String,
        val service: String,
        val day: String,
    )

    val customers = listOf(
        Customer("Dana Reyes", "555-0117", "Trek FX 3", "March 2026"),
        Customer("Priya Natarajan", "555-0198", "Specialized Sirrus", "June 2026"),
    )

    private val _leads = MutableStateFlow(initialLeads)
    val leads: StateFlow<List<Lead>> = _leads.asStateFlow()

    private val _appointments = MutableStateFlow<List<Appointment>>(emptyList())
    val appointments: StateFlow<List<Appointment>> = _appointments.asStateFlow()

    private var nextAppointmentNumber = 1042

    fun lead(id: String): Lead? = _leads.value.firstOrNull { it.id == id }

    /** Case-insensitive lookup; null when the customer is unknown. */
    fun lookupCustomer(name: String): Customer? = customers.firstOrNull {
        it.name.contains(name, ignoreCase = true) || name.contains(it.name, ignoreCase = true)
    }

    /** Books an appointment and returns it with its confirmation id. */
    fun bookAppointment(customerName: String, service: String, day: String): Appointment {
        val appointment = Appointment("A-${nextAppointmentNumber++}", customerName, service, day)
        _appointments.update { it + appointment }
        return appointment
    }

    fun markLeadHandled(id: String) = updateLead(id) { it.copy(status = Lead.Status.HANDLED) }

    fun markLeadInProgress(id: String) = updateLead(id) {
        if (it.status == Lead.Status.NEW) it.copy(status = Lead.Status.IN_PROGRESS) else it
    }

    private fun updateLead(id: String, transform: (Lead) -> Lead) {
        _leads.update { leads -> leads.map { if (it.id == id) transform(it) else it } }
    }
}
