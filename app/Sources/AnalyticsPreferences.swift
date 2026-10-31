import SwiftUI

struct AnalyticsConsentBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy-focused usage analytics").font(.headline)
            Text("Usage analytics is on to help improve Deployed Yet? We send limited feature events and a random installation identifier to PostHog, never tokens, project names, repositories, paths, or deployment content. Turn it off here or in General → Privacy.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Got it") { Analytics.shared.setConsent(true) }
                Button("Turn off analytics") { Analytics.shared.setConsent(false) }
                Spacer()
                Link("Privacy details", destination: URL(string: "https://deployedyet.com/privacy")!)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnalyticsPreferences: View {
    private var analytics: Analytics { .shared }

    var body: some View {
        Toggle(isOn: Binding(
            get: { analytics.consent == .enabled },
            set: { analytics.setConsent($0) }
        )) {
            Text("Share usage analytics")
            Text("Help improve the app with usage events, a random installation identifier, app version, macOS major version, and coarse setup counts. No tokens, project names, repositories, file paths, or deployment content.")
        }
        Text("On by default in configured release builds. Turning this off stops collection, discards queued events, and removes the local analytics identifier. It does not delete events already sent. PostHog receives your network address when connecting; location enrichment is disabled.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if !analytics.configured {
            Label("Analytics is not configured in this build. Nothing is sent.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if analytics.debugDisabled {
            Label("Analytics is disabled for this debug build. Nothing is sent.", systemImage: "hammer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Link("Read the privacy policy", destination: URL(string: "https://deployedyet.com/privacy")!)
    }
}
