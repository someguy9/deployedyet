import SwiftUI

struct MenuView: View {
    @Environment(Store.self) private var store
    @State private var filter = DeployFilter()
    @FocusState private var searchFocused: Bool

    private var matchingRows: [Deploy] { store.rows.filter(filter.matches) }

    /// Now first, then by day, like an activity feed: Failed, In progress, Today, This week, Earlier.
    private var sections: [(title: String, rows: [Deploy])] {
        let order = ["Failed", "In progress", "Today", "This week", "Earlier"]
        let groups = Dictionary(grouping: matchingRows) { d -> String in
            switch d.state {
            case .failed where d.isRecentFailure: "Failed" // older failures sort by date with the rest
            case .building: "In progress"
            default:
                Calendar.current.isDateInToday(d.createdAt) ? "Today"
                    : Date.now.timeIntervalSince(d.createdAt) < 7 * 86_400 ? "This week" : "Earlier"
            }
        }
        return order.compactMap { title in groups[title].map { (title, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.accounts.isEmpty {
                empty("Connect Vercel, Cloudflare or GitHub and your menu bar will start answering.", button: "Add a token…")
            } else if store.projects.isEmpty && store.monitoringDegraded {
                empty("Couldn't check your accounts. Showing no deployment information yet.", button: "Open Settings…")
            } else if store.projects.isEmpty && store.lastSuccessfulChecks.isEmpty {
                empty("Checking your deploys…", button: nil)
            } else if store.projects.isEmpty {
                empty("No projects in your accounts yet. Deploy something and it shows up here.", button: "Open Settings…")
            } else if store.rows.isEmpty {
                empty("Nothing picked. Your menu bar is very calm.", button: "Pick projects…")
            } else {
                header
                Divider().padding(.horizontal, 14)
                filters
                if matchingRows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No matching deployments").font(.callout.weight(.semibold))
                        Text("Try another search or clear your filters.").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                } else {
                ScrollView {
                    // Only label the parts of a row that differ between rows: one team or one provider is noise.
                    let showTeam = Set(store.rows.map(\.team)).count > 1
                    let showProvider = Set(store.rows.map(\.provider)).count > 1
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.title) { section in
                            if sections.count > 1 || section.title == "Failed" {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(section.title == "Failed" ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                    .padding(.horizontal, 10)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            // Keyed by the whole deploy, not its id: a row that went building → ready while the menu sat
                            // open (or hidden) was being reused as-is, spinner and all.
                            ForEach(section.rows, id: \.self) { DeployRow(deploy: $0, showTeam: showTeam, showProvider: showProvider) }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 440)
                .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(store.accounts.filter { store.errors[$0.id] != nil }) { account in
                Label("\(account.label): \(store.errors[account.id] ?? "")", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Divider()

            HStack(spacing: 14) {
                Button { Task { await store.refreshNow() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Refresh now (⌘R)")
                Spacer()
                Button { openAndClose(URL(string: "https://buymeacoffee.com/someguy")) } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer")
                }
                .help("Buy me a coffee")
                Button(action: showSettings) { Label("Settings", systemImage: "gearshape") }
                    .keyboardShortcut(",")
                    .help("Settings (⌘,)")
                Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
                    .keyboardShortcut("q")
                    .help("Quit Deployed Yet? (⌘Q)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 380)
    }

    private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("f")
                    .accessibilityLabel("Focus deployment search")
                    .help("Search deployments (⌘F)")
                TextField("Search deployments", text: $filter.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityLabel("Search deployments")
            }
            HStack(spacing: 8) {
                Picker("Provider", selection: $filter.provider) {
                    Text("All providers").tag(nil as Provider?)
                    ForEach(Provider.allCases, id: \.self) { provider in
                        Text(provider.name).tag(Optional(provider))
                    }
                }
                .accessibilityLabel("Filter by provider")
                Picker("State", selection: $filter.state) {
                    Text("All states").tag(nil as DeployState?)
                    ForEach([DeployState.failed, .building, .ready, .canceled], id: \.self) { state in
                        Text(state.label).tag(Optional(state))
                    }
                }
                .accessibilityLabel("Filter by deployment state")
                Button("Clear") { filter = DeployFilter() }
                    .help("Clear search and filters")
                    .accessibilityLabel("Clear search and filters")
            }
            .labelsHidden()
            HStack {
                Text("\(matchingRows.count) of \(store.rows.count) deployments")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// Big answer up top: a badge matching the menu bar glyph, the headline, and a one-line summary.
    private var header: some View {
        HStack(spacing: 12) {
            StatusBadge(state: store.monitoringDegraded ? .failed : store.overall)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.headline).font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let rows = store.rows
        let providers = Set(rows.map(\.provider)).count
        var parts = ["\(rows.count) project\(rows.count == 1 ? "" : "s")"]
        if providers > 1 { parts.append("\(providers) providers") }
        if let newest = rows.map(\.createdAt).max(), store.overall != .building {
            parts.append("last deploy \(newest.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func empty(_ text: String, button: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).foregroundStyle(.secondary)
            if let button { Button(button, action: showSettings) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private func showSettings() {
        closeMenu()
        SettingsWindow.show(store)
    }
}

/// Row status mark. Ready is a quiet dot (most rows are ready); trouble and progress get the weight.
struct StatusIcon: View {
    let state: DeployState
    /// A failure from more than a week ago: still marked, but muted.
    var stale = false

    var body: some View {
        Group {
            switch state {
            case .building: ProgressView().controlSize(.mini)
            case .ready: Circle().fill(.green).frame(width: 7, height: 7)
            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(stale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            case .canceled: Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 7, height: 7)
            }
        }
        .font(.system(size: 13))
        .frame(width: 16, height: 16)
        .accessibilityElement()
        .accessibilityLabel(state.label)
    }
}

/// Header badge: the menu bar answer, as a soft tinted chip rather than a loud filled circle.
struct StatusBadge: View {
    let state: DeployState?

    var body: some View {
        let (symbol, color): (String, Color) = switch state {
        case .failed: ("exclamationmark", .red)
        case .building: ("questionmark", .orange)
        case .ready, .canceled: ("checkmark", .green)
        case nil: ("questionmark", .gray)
        }
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.16), in: .circle)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// The MenuBarExtra panel is the key window while open; closing it is how the menu "dismisses".
@MainActor func closeMenu() {
    NSApp.keyWindow?.close()
}

@MainActor func openAndClose(_ url: URL?) {
    // Links are built from API data: only ever hand the browser a web page, never a file:// or app scheme.
    guard let url, url.scheme == "https" else { return }
    closeMenu()
    NSWorkspace.shared.open(url)
}

struct DeployRow: View {
    @Environment(Store.self) private var store
    let deploy: Deploy
    var showTeam = true
    var showProvider = true
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusIcon(state: deploy.state, stale: deploy.state == .failed && !deploy.isRecentFailure)
                .padding(.top, 1) // optical: centers on the project name's line

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(deploy.projectName).fontWeight(.medium)
                    if !deploy.isProduction {
                        Text("preview").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if deploy.state == .building {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("building \(Duration.seconds(max(0, context.date.timeIntervalSince(deploy.createdAt))).formatted(.time(pattern: .minuteSecond)))")
                                .font(.caption)
                                .foregroundStyle(DeployState.building.color)
                                .monospacedDigit()
                        }
                    } else {
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            // wrangler deploys have no build phase, so flag fresh ones for ~2 minutes instead.
                            let fresh = deploy.isManual && context.date.timeIntervalSince(deploy.createdAt) < 120
                            Text(fresh ? "just shipped" : deploy.createdAt.shortAgo(at: context.date))
                                .font(.caption)
                                .foregroundStyle(fresh ? AnyShapeStyle(DeployState.ready.color)
                                    : deploy.isRecentFailure ? AnyShapeStyle(DeployState.failed.color) : AnyShapeStyle(.secondary))
                                .monospacedDigit()
                        }
                    }
                }
                if let message = deploy.message?.components(separatedBy: .newlines).first, !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    if showProvider {
                        ProviderLogo(provider: deploy.provider, size: 9)
                            .opacity(0.8)
                            .padding(.trailing, 1)
                    }
                    // Vercel-style meta line: where it came from (branch + short SHA), then where it went.
                    if let branch = deploy.branch {
                        Image(systemName: "arrow.triangle.branch").imageScale(.small)
                        Text(branch).lineLimit(1).truncationMode(.middle)
                    }
                    if let sha = deploy.shortCommit {
                        Text(sha).monospaced()
                    }
                    if let tail = metaTail {
                        Text(tail).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if deploy.state == .building {
                let isWatched = store.watched.contains(deploy.id)
                Button { store.toggleWatch(deploy.id) } label: {
                    Image(systemName: isWatched ? "bell.fill" : "bell")
                        .foregroundStyle(isWatched ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .help(isWatched ? "Watching. You'll get a notification when it finishes." : "Notify me when this finishes")
                .accessibilityLabel(isWatched ? "Stop watching" : "Notify me when this finishes")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { open(deploy.url) }
        // VoiceOver: one element per row that reads like the row looks, with the extras as named actions.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(deploy.url) }
        .accessibilityAction(named: store.watched.contains(deploy.id) ? "Stop watching" : "Notify me when it finishes") {
            if deploy.state == .building { store.toggleWatch(deploy.id) }
        }
        .accessibilityAction(named: "Open site") { open(deploy.siteURL) }
        .accessibilityAction(named: "Production only") { store.toggleProductionOnly(deploy.projectID) }
        .help("Open this deploy. Right-click for more.")
        .contextMenu {
            Button("Open deploy") { open(deploy.url) }
            Button("Open site") { open(deploy.siteURL) }.disabled(deploy.siteURL == nil)
            Button("Open project") { open(deploy.projectURL) }.disabled(deploy.projectURL == nil)
            Button("Copy site URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deploy.siteURL?.absoluteString ?? "", forType: .string)
            }
            .disabled(deploy.siteURL == nil)
            Divider()
            if store.trackPreviews {
                Toggle("Production only", isOn: Binding(
                    get: { store.productionOnly.contains(deploy.projectID) },
                    set: { _ in store.toggleProductionOnly(deploy.projectID) }
                ))
            }
            Button("Stop tracking \(deploy.projectName)") { store.untrack(deploy.projectID) }
        }
    }

    private func open(_ url: URL?) {
        guard url != nil else { return }
        Analytics.shared.capture(.deploymentOpened)
        openAndClose(url)
    }

    /// "· Team · built in 48s", leaving out whatever is the same on every row.
    private var metaTail: String? {
        let bare = deploy.branch == nil && deploy.shortCommit == nil
        let team: String? = showTeam || bare ? deploy.team : nil
        let built: String? = deploy.duration.map {
            "built in " + Duration.seconds($0).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
        }
        let parts = [team, built].compactMap { $0 }
        if parts.isEmpty { return nil }
        return (bare ? "" : "· ") + parts.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        let when = deploy.createdAt.formatted(.relative(presentation: .named))
        return [deploy.projectName, deploy.isProduction ? nil : "preview", deploy.state.label, when,
                deploy.message?.components(separatedBy: .newlines).first, deploy.branch.map { "branch \($0)" }, deploy.team]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

extension Date {
    /// "5m ago", but "just now" for the first seconds, where Foundation says "in 0s" (or "in 3s" when a provider's clock runs ahead).
    func shortAgo(at now: Date) -> String {
        now.timeIntervalSince(self) < 10 ? "just now" : formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }
}
