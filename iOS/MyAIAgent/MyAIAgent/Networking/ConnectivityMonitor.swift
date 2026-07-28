//
//  ConnectivityMonitor.swift
//  MyAIAgent
//

import Foundation
import Network
import Observation

/// Connectivity as first-class observable state (ADR 0001): the UI routes
/// on it proactively — offline is a mode, not an error inferred after a
/// failed request. The protocol is the seam; tests and previews inject a
/// scripted stub instead of the real path monitor.
@MainActor
protocol ConnectivityMonitoring: AnyObject, Observable {
    var isOnline: Bool { get }
}

/// Production monitor backed by NWPathMonitor. App-scoped: created once at
/// launch and lives for the process, so there is no teardown path.
@Observable
final class ConnectivityMonitor: ConnectivityMonitoring {
    private(set) var isOnline = true

    init() {
        // The path handler runs on the monitor's queue; bridge updates onto
        // the main actor through an AsyncStream so no non-Sendable state
        // crosses the boundary.
        let updates = AsyncStream<Bool> { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { @Sendable path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "connectivity-monitor"))
        }
        Task { [weak self] in
            for await online in updates {
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
            }
        }

        // Reconnect watchdog: a long-lived NWPathMonitor does not always
        // deliver the satisfied update when the network returns (the
        // simulator drops it routinely), but a FRESH monitor's initial
        // path report is reliable everywhere. Probe with one while offline
        // so the app can never get stuck in offline mode.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                if !self.isOnline, await Self.freshMonitorReportsSatisfied() {
                    self.isOnline = true
                }
            }
        }
    }

    /// Spins up a throwaway NWPathMonitor and returns its initial path
    /// verdict — the reliable way to ask "are we online right now?".
    private static func freshMonitorReportsSatisfied() async -> Bool {
        let firstPath = AsyncStream<Bool> { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { @Sendable path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "connectivity-probe"))
        }
        var iterator = firstPath.makeAsyncIterator()
        return await iterator.next() ?? false
    }
}

#if DEBUG
/// Scripted monitor for previews and tests: set `isOnline` to drive
/// offline/online transitions deterministically.
@Observable
final class StubConnectivityMonitor: ConnectivityMonitoring {
    var isOnline: Bool

    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }
}
#endif
