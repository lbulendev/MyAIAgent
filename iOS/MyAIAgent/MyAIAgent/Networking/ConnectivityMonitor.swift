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
