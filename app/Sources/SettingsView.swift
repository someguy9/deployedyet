import ServiceManagement
import SwiftUI

private enum Pane: Hashable {
    case account(UUID), add, general, appearance
}

/// Two columns: accounts + General on the left, the picked pane on the right.
/// Hand-built instead of NavigationSplitView: in a Settings window that ignores column widths and squeezes the sidebar.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @State private var pane: Pane?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 250)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, idealWidth: 860, minHeight: 560, idealHeight: 620)
        .onChange(of: title, initial: true) { _, new in SettingsWindow.setTitle(new) }
        .task { await store.refresh(full: true) } // pick up projects created since the last poll
        .onAppear {
            if pane == nil { pane = store.accounts.first.map { .account($0.id) } ?? .add }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { pane }, set: { if let new = $0 { pane = new } })) { // never deselect
                Section("Accounts") {
                    ForEach(store.accounts) { account in
                        AccountSidebarRow(account: account).tag(Pane.account(account.id))
                    }
                    if store.accounts.isEmpty {
                        Text("None yet").foregroundStyle(.secondary)
                    }
                }
                Section("App") {
                    Label("General", systemImage: "gearshape").tag(Pane.general)
                    Label("Appearance", systemImage: "paintbrush").tag(Pane.appearance)
                }
            }
            .listStyle(.sidebar)

            Divider()
            // Like Mail's account list: adding lives at the bottom, not as a fake account row.
            Button { pane = .add } label: {
                Label("Add Account", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(pane == .add ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .help("Connect Vercel, Cloudflare or GitHub")
        }
        .background(.background.secondary)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .account(let id):
            if let account = store.accounts.first(where: { $0.id == id }) {
                AccountPane(account: account) { pane = store.accounts.first.map { .account($0.id) } ?? .add }
                    .id(id) // fresh filter per account
            } else {
                AddAccountPane { pane = .account($0) }
            }
        case .general:
            GeneralPane()
        case .appearance:
            AppearancePane()
        case .add, nil:
            AddAccountPane { pane = .account($0) }
        }
    }

    private var title: String {
        switch pane {
        case .account(let id): store.accounts.first { $0.id == id }?.label ?? "Settings"
        case .general: "General"
        case .appearance: "Appearance"
        case .add, nil: "Add Account"
        }
    }
}

private struct AccountSidebarRow: View {
    @Environment(Store.self) private var store
    let account: Account

    var body: some View {
        let all = store.projects.filter { $0.accountID == account.id }
        let picked = all.filter { store.selected.contains($0.id) }.count
        let failing = store.errors[account.id] != nil
        HStack(spacing: 10) {
            ProviderLogo(provider: account.provider, size: 14)
                .frame(width: 28, height: 28)
                .background(.fill.tertiary, in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(account.label).lineLimit(1).truncationMode(.tail)
                Text(failing ? "Needs attention" : "\(account.provider.name) · \(picked) of \(all.count)")
                    .font(.caption)
                    .foregroundStyle(failing ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        // One element: the logo already says the provider, and "3 of 12" needs its noun when spoken.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.label), \(account.provider.name), "
            + (failing ? "needs attention" : "\(picked) of \(all.count) projects picked"))
    }
}

// MARK: - Account

private struct AccountPane: View {
    @Environment(Store.self) private var store
    let account: Account
    let onRemove: () -> Void
    @State private var query = ""
    @State private var confirmRemove = false
    @State private var checking = false // only a refresh asked for here spins; background polls would flicker it

    var body: some View {
        let all = store.projects.filter { $0.accountID == account.id }
        let shown = all
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let teams = Dictionary(grouping: shown, by: \.group) // id, not name: two teams can share a name
            .map { (id: $0.key, name: $0.value[0].team, projects: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        Form {
            Section {
                HStack(spacing: 14) {
                    ProviderLogo(provider: account.provider, size: 22)
                        .frame(width: 44, height: 44)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Label", text: Binding(
                            get: { account.label },
                            set: { store.rename(account.id, to: $0) }
                        ))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .help("Click to rename")
                        .onSubmit { store.finishRename(account.id) }
                        .onDisappear { store.finishRename(account.id) }
                        let teamCount = Set(all.map(\.group)).count
                        Text("\(account.provider.name) · \(all.filter { store.selected.contains($0.id) }.count) of \(all.count) picked · \(teamCount) \(account.provider == .vercel ? "team" : account.provider == .github ? "owner" : "account")\(teamCount == 1 ? "" : "s")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        let ok = store.errors[account.id] == nil
                        let checked = store.lastSuccessfulChecks[account.id]
                        HStack(spacing: 5) {
                            Circle().fill(!ok ? Color.red : checked == nil ? .gray : .green).frame(width: 6, height: 6)
                            Text(!ok ? "Needs attention" : checked == nil ? "Not checked yet" : "Connected")
                            if let checked {
                                Text("· last full check \(checked.formatted(.relative(presentation: .named)))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    }
                    Spacer()
                    if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            checking = true
                            Task {
                                await store.refresh(full: true)
                                checking = false
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Check for new projects")
                        .accessibilityLabel("Refresh projects")
                    }
                }
                .padding(.vertical, 4)
                if let error = store.errors[account.id] {
                    Text(error).foregroundStyle(.red)
                }
                if all.count > 12 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter", text: $query, prompt: Text("Filter \(all.count) projects"))
                            .labelsHidden()
                            .textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Clear filter")
                        }
                    }
                }
            }

            if all.isEmpty {
                Text(store.errors[account.id] == nil ? "No projects yet." : "Couldn't load projects.")
                    .foregroundStyle(.secondary)
            }

            ForEach(teams, id: \.id) { team in
                let projects = team.projects
                Section {
                    ForEach(projects) { ProjectToggle(project: $0) }
                } header: {
                    let picked = projects.filter { store.selected.contains($0.id) }.count
                    HStack {
                        Text(team.name)
                        Text("\(picked) of \(projects.count)").foregroundStyle(.secondary)
                        Spacer()
                        Button(picked == projects.count ? "None" : "All") {
                            let ids = projects.map(\.id)
                            if picked == projects.count { store.selected.subtract(ids) } else { store.selected.formUnion(ids) }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove account")
                        Text("Deletes the token from Keychain. Add it again any time; your picks come back.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove…", role: .destructive) { confirmRemove = true }
                        .tint(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(account.label)
        .confirmationDialog("Remove \(account.label)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                store.removeAccount(account)
                onRemove()
            }
        } message: {
            Text("The token is deleted from Keychain. You can add it again any time.")
        }
    }
}

private struct ProjectToggle: View {
    @Environment(Store.self) private var store
    let project: Project

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.selected.contains(project.id) },
            set: { on in
                if on { store.selected.insert(project.id) } else { store.selected.remove(project.id) }
            }
        )) {
            Text(project.name)
            if let last = project.latest.first {
                Text("Deployed \(last.createdAt.formatted(.relative(presentation: .named)))")
            } else if let pushed = project.activity {
                Text("Pushed \(pushed.formatted(.relative(presentation: .named)))")
            }
        }
        .contextMenu {
            Toggle("Production only", isOn: Binding(
                get: { store.productionOnly.contains(project.id) },
                set: { _ in store.toggleProductionOnly(project.id) }
            ))
        }
    }
}

// MARK: - Add

private struct AddAccountPane: View {
    @Environment(Store.self) private var store
    let onAdded: (UUID) -> Void
    @State private var provider = Provider.vercel
    @State private var label = ""
    @State private var token = ""
    @State private var adding = false
    @State private var error: String?
    @FocusState private var tokenFocused: Bool

    private var trimmed: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect an account").font(.title2.weight(.semibold))
                    Text("Pick where you deploy. Add as many accounts as you like.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    ForEach(Provider.allCases, id: \.self) { p in
                        ProviderCard(provider: p, selected: p == provider) {
                            provider = p
                            error = nil
                            tokenFocused = true
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Create a token") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(provider.tokenHelp).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Link("Open \(provider.name) tokens ↗", destination: provider.tokenURL)
                        }
                    }
                    step(2, "Paste it here") {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Token", text: $token, prompt: Text("\(provider.name) API token"))
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                                .focused($tokenFocused)
                                .onSubmit(add)
                            TextField("Label", text: $label, prompt: Text("Name (optional, filled in from \(provider.name))"))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(add)
                        }
                    }
                }
                .padding(16)
                .background(.fill.quinary, in: .rect(cornerRadius: 10))

                HStack(alignment: .firstTextBaseline) {
                    Label("Stored in your Keychain. Only ever sent to \(provider.apiHost).", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if adding { ProgressView().controlSize(.small) }
                    Button("Connect \(provider.name)", action: add)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmed.isEmpty || adding)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .navigationTitle("Add Account")
        .onAppear { tokenFocused = true }
    }

    private func step(_ n: Int, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(.fill.tertiary))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    private func add() {
        guard !adding, !trimmed.isEmpty else { return }
        adding = true
        error = nil
        Task {
            defer { adding = false }
            do {
                let account = try await store.addAccount(provider: provider, label: label, token: trimmed)
                label = ""
                token = ""
                onAdded(account.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Environment(Store.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = Updater.shared
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle(isOn: $store.trackPreviews) {
                    Text("Track preview deploys")
                    Text("Turn off if your repos build previews all day. Right-click a project for production only.")
                }
                Toggle(isOn: Binding(
                    get: { store.watchPushes },
                    set: { on in
                        if on, store.pushFolder == nil { // first time: ask where the repos live
                            guard let folder = chooseFolder() else { return }
                            store.pushFolder = folder
                        }
                        store.watchPushes = on
                    }
                )) {
                    Text("Check right after I push")
                    Text("Watches a folder of your git repos, then checks every 5 seconds for a minute after a push. It only reads git’s push log there, and nothing leaves your Mac.")
                }
                if store.watchPushes, let folder = store.pushFolder {
                    LabeledContent("Repos folder") {
                        HStack(spacing: 8) {
                            Text((folder as NSString).abbreviatingWithTildeInPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Change…") {
                                if let folder = chooseFolder() { store.pushFolder = folder }
                            }
                        }
                    }
                }
            }

            Section("Notify me when") {
                Toggle("A deploy fails", isOn: $store.notifyFailed)
                Toggle("Production is live", isOn: $store.notifyReady)
                Text("Click the bell on a building deploy to hear about that one no matter what.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deployed Yet?").font(.title3.weight(.semibold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") · Free and open source")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Toggle(isOn: $updater.automatic) {
                    Text("Install updates automatically")
                    Text("Checks GitHub once a day and swaps in the new version while nothing is building.")
                }
                LabeledContent("Updates") {
                    Button("Check for Updates…") { updater.checkNow() }
                        .disabled(!updater.canCheck)
                }
                LabeledContent("Privacy") {
                    Text("Tokens stay in Keychain and only go to the APIs of the accounts you add. Update checks send no tokens.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                Link("Send feedback or report a bug", destination: URL(string: "https://github.com/someguy9/deployedyet/issues/new")!)
                Link("Website", destination: URL(string: "https://deployedyet.com")!)
                Link("Source on GitHub", destination: URL(string: "https://github.com/someguy9/deployedyet")!)
                Link("☕︎ Buy me a coffee", destination: URL(string: "https://buymeacoffee.com/someguy")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        panel.message = "Pick the folder your git repos live in, like ~/Code."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// Everything about how the menu bar icon looks, with the real glyphs previewed at the top.
private struct AppearancePane: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                // Drawn by the same Glyph code as the menu bar, so this is exactly what you'll see up there.
                TimelineView(.periodic(from: .now, by: 0.12)) { context in
                    let frame = store.animateIcon && !reduceMotion ? Int(context.date.timeIntervalSinceReferenceDate / 0.12) : 0
                    HStack(spacing: 0) {
                        preview(.building, "Building", frame: frame)
                        preview(.ready, store.iconColor == .automatic ? "Just landed" : "Live", frame: frame)
                        preview(.failed, "Failed", frame: frame)
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                Picker(selection: $store.iconOnlyWhenBusy) {
                    Text("Always").tag(false)
                    Text("Only while building or failed").tag(true)
                } label: {
                    Text("Show menu bar icon")
                    Text(store.iconOnlyWhenBusy
                         ? "Open Deployed Yet? again from Spotlight or Finder to get back here while it's hidden."
                         : "Always there, ? / ✓ / ! at a glance.")
                }
                Picker(selection: $store.iconStyle) {
                    ForEach(IconStyle.allCases) { style in
                        Image(systemName: style.symbol(.ready))
                            .accessibilityLabel(style.label)
                            .help(style.label)
                            .tag(style)
                    }
                } label: {
                    Text("Icon style")
                    Text("Every style answers the same way: open while building, settled when it ships, ! when it fails.")
                }
                .pickerStyle(.segmented)
                Picker(selection: $store.iconColor) {
                    ForEach(IconColor.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("Icon color")
                    Text("Automatic: amber while building, green for 5 minutes after a deploy lands, red while something's failed.")
                }
                Toggle(isOn: $store.animateIcon) {
                    Text("Animate icon")
                    Text("The ? rocks while building, then turns into the answer when it lands.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }

    private func preview(_ state: DeployState, _ title: String, frame: Int) -> some View {
        VStack(spacing: 8) {
            Image(nsImage: Glyph.image(state, frame: frame, style: store.iconStyle, color: store.iconColor, fresh: true))
                .frame(width: 18, height: 18)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.fill.tertiary, in: .rect(cornerRadius: 6)) // sits like a menu bar item
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) icon")
    }
}
