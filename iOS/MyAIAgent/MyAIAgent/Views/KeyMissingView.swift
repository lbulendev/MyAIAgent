//
//  KeyMissingView.swift
//  MyAIAgent
//

import SwiftUI

/// Shown instead of the app when no API key was injected at build time —
/// fail fast with instructions, never a crash and never a hardcoded key.
struct KeyMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "key_missing_title", defaultValue: "API Key Missing"),
                systemImage: "key.slash"
            )
        } description: {
            Text(String(
                localized: "key_missing_body",
                defaultValue: "Copy Secrets.xcconfig.template to Secrets.xcconfig, set ANTHROPIC_API_KEY, and rebuild. See the README for details."
            ))
        }
    }
}

#if DEBUG
#Preview {
    KeyMissingView()
}
#endif
