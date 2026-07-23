//
//  ErrorBanner.swift
//  MyAIAgent
//

import SwiftUI

/// Maps agent errors to the localized copy users see — raw error text
/// never reaches the screen (same pattern as HeartChart and TheMovieDBSwift).
extension AgentError {
    var message: String {
        switch self {
        case .offline:
            String(localized: "error_offline", defaultValue: "You appear to be offline.")
        case .server:
            String(localized: "error_server", defaultValue: "The service is having trouble right now.")
        case .generic:
            String(localized: "error_generic", defaultValue: "Something went wrong.")
        }
    }
}

/// The single error surface: a red banner with a friendly message and a
/// Retry button that replays the failed run. Persists until retry succeeds.
struct ErrorBanner: View {
    let error: AgentError
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "retry", defaultValue: "Retry"), action: retry)
                .font(.subheadline.weight(.bold))
                .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.red, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Offline") {
    ErrorBanner(error: .offline) {}
}

#Preview("Server") {
    ErrorBanner(error: .server) {}
}
#endif
