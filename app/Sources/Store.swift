import AppKit
import Observation
import UserNotifications

@MainActor @Observable
final class Store {
    var accounts: [Account] { didSet { save(accounts, "accounts") } }
    var selected: Set<String> {
        didSet {
            save(selected, "selected")
            updateWobble()
        }
    }
    /// Projects that ignore previews even when `trackPreviews` is on.
    /// Every project id the app has seen, so a new one can be picked on arrival and an unticked one stays unticked.
    /// nil until the first full refresh after an upgrade, which records what's there without picking any of it.
    private var known: Set<String>? { didSet { save(known, "knownProjects") } }
    var productionOnly: Set<String> {
        didSet {
            save(productionOnly, "productionOnly")
            forgetSeen()
            updateWobble()
        }
    }
    var trackPreviews: Bool {
        didSet {
            UserDefaults.standard.set(trackPreviews, forKey: "trackPreviews")
            forgetSeen()
            updateWobble()
        }
    }
    var notifyFailed: Bool { didSet { UserDefaults.standard.set(notifyFailed, forKey: "notifyFailed") } }
    var notifyReady: Bool { didSet { UserDefaults.standard.set(notifyReady, forKey: "notifyReady") } }
    var watched: Set<String> = []
    private(set) var projects: [Project] = []
    private(set) var errors: [UUID: String] = [:]
    private(set) var lastSuccessfulChecks: [UUID: Date] = [:]
    private var lastAttempt: Date?
    var monitoringDegraded: Bool { !errors.isEmpty }
    /// Menu bar wobble frame while something builds. Only the label reads it.
    private(set) var wobbleFrame = 0
    /// One-shot ?→✓ / ?→! animation when the last build lands.
    private(set) var morph: (to: DeployState, frame: Int)?
    /// True for a few minutes after a build lands, so Automatic icon color keeps the ✓ green that long.
    private(set) var freshLanding = false
    private var freshTask: Task<Void, Never>?
    var iconColor: IconColor { didSet { UserDefaults.standard.set(iconColor.rawValue, forKey: "iconColor") } }
    var iconStyle: IconStyle { didSet { UserDefaults.standard.set(iconStyle.rawValue, forKey: "iconStyle") } }
    /// The ? rocks while building and morphs into the answer; off keeps the icon still.
    var animateIcon: Bool { didSet { UserDefaults.standard.set(animateIcon, forKey: "animateIcon"); updateWobble() } }
    /// Show the menu bar icon only while something needs a look.
    var iconOnlyWhenBusy: Bool { didSet { UserDefaults.standard.set(iconOnlyWhenBusy, forKey: "iconOnlyWhenBusy") } }
    /// Keeps a hidden-when-idle icon around for a few seconds after a build lands, so the ✓ / ! is seen.
    private(set) var justLanded = false
    /// The menu panel is open; a hidden-when-idle icon must not vanish from under it.
    var menuOpen = false { didSet { if menuOpen && !oldValue { menuDidOpen() } } }
    /// Opt-in: watch a folder of git repos and check right after a push (see PushWatcher).
    var watchPushes: Bool { didSet { UserDefaults.standard.set(watchPushes, forKey: "watchPushes"); updatePushWatcher() } }
    var pushFolder: String? { didSet { UserDefaults.standard.set(pushFolder, forKey: "pushFolder"); updatePushWatcher() } }
    private var pushWatcher: PushWatcher?
    /// After a push: check every 5s for a minute, or until the new build shows up.
    private var burstUntil: Date?
    private var napTask: Task<Void, Never>?
    private var lastOverall: DeployState?
    private var morphTask: Task<Void, Never>?
    private var justFinished = false

    /// Last known state of every tracked deploy, and which picked projects we've already looked at.
    private var seen: [String: DeployState] = [:]
    private var seenProjects: Set<String> = []
    private(set) var refreshing = false
    private var lastFull: Date?
    private var lastPicked: Date?
    private var fullUnreachable: [UUID: [TeamRef]] = [:]
    private var accountErrors: [UUID: String] = [:]
    private var backoff: [UUID: Date] = [:]
    private var wobbleTask: Task<Void, Never>?
    private let notificationDelegate = NotificationDelegate()

    init() {
        accounts = Self.load("accounts") ?? []
        selected = Self.load("selected") ?? []
        known = Self.load("knownProjects")
        productionOnly = Self.load("productionOnly") ?? []
        trackPreviews = UserDefaults.standard.object(forKey: "trackPreviews") as? Bool ?? true
        notifyFailed = UserDefaults.standard.object(forKey: "notifyFailed") as? Bool ?? true
        notifyReady = UserDefaults.standard.object(forKey: "notifyReady") as? Bool ?? true
        // "colorIcon" was the old on/off switch: on meant always; off gets the new default, automatic.
        iconColor = UserDefaults.standard.string(forKey: "iconColor").flatMap(IconColor.init)
            ?? (UserDefaults.standard.bool(forKey: "colorIcon") ? .always : .automatic)
        iconStyle = UserDefaults.standard.string(forKey: "iconStyle").flatMap(IconStyle.init) ?? .plain
        animateIcon = UserDefaults.standard.object(forKey: "animateIcon") as? Bool ?? true
        iconOnlyWhenBusy = UserDefaults.standard.bool(forKey: "iconOnlyWhenBusy")
        watchPushes = UserDefaults.standard.bool(forKey: "watchPushes")
        pushFolder = UserDefaults.standard.string(forKey: "pushFolder")
        if let cache = Self.readCache() { // last-known rows instantly, honest "Updated 2h ago" until the first poll
            projects = cache.projects.filter { p in accounts.contains { $0.id == p.accountID } }
            lastSuccessfulChecks = (cache.successfulChecks ?? [:]).filter { id, _ in accounts.contains { $0.id == id } }
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Right after a push the new deploy can be on any picked project, so look at all of them.
                if inPushBurst && !anyBuilding { lastPicked = nil }
                await refresh()
                if anyBuilding { burstUntil = nil } // it showed up; the normal building cadence takes over
                let busy = anyBuilding || inPushBurst // not `overall`: an old failure elsewhere outranks building
                // No full refresh has worked yet (e.g. launched at login before Wi-Fi): retry soon.
                let offline = lastFull == nil && !errors.isEmpty
                await nap(busy ? 5 : offline ? 10 : 60)
            }
        }
        // After sleep the data is stale and the poll loop may be mid-60s; look right away.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3)) // Wi-Fi usually needs a moment
                await self?.refresh(full: true)
            }
        }
        updatePushWatcher() // property observers don't run in init
    }

    /// One row per picked project: its newest tracked deploy. Failed first (needs you), then building, then newest.
    var rows: [Deploy] {
        projects
            .filter { selected.contains($0.id) }
            .compactMap { tracked($0).first }
            .sorted { a, b in
                let rank = { (d: Deploy) in d.isRecentFailure ? 0 : d.state == .building ? 1 : 2 }
                return rank(a) != rank(b) ? rank(a) < rank(b) : a.createdAt > b.createdAt
            }
    }

    private func tracked(_ project: Project) -> [Deploy] {
        let previews = trackPreviews && !productionOnly.contains(project.id)
        return project.latest.filter { previews || $0.isProduction }
    }

    /// Any tracked deploy of a picked project still building, top row or not.
    var anyBuilding: Bool {
        projects.contains { selected.contains($0.id) && tracked($0).contains { $0.state == .building } }
    }

    var showsIcon: Bool {
        !iconOnlyWhenBusy || accounts.isEmpty || menuOpen || justLanded || monitoringDegraded || overall == .building || overall == .failed
    }

    /// nil = nothing picked.
    /// An old failure counts as settled (like a cancel), so it never turns the menu bar red.
    var overall: DeployState? { rows.map { $0.state == .failed && !$0.isRecentFailure ? .canceled : $0.state }.max() }

    /// The app's name is a question. This is the answer.
    var headline: String {
        let rows = rows
        let failed = rows.filter(\.isRecentFailure)
        let building = rows.filter { $0.state == .building }
        if let first = failed.first {
            return failed.count == 1 ? "Nope. \(first.projectName) failed." : "Nope. \(failed.count) failed."
        }
        if monitoringDegraded { return "Monitoring needs attention." }
        if !building.isEmpty { return "Not yet. \(building.count) building." }
        return rows.isEmpty ? "Nothing picked." : "Yep. All deployed."
    }

    /// Full = every team of every account: at launch, when Settings opens, every 10 minutes, and after any failure.
    /// Otherwise only teams with picked projects, and on fast 5s "something is building" ticks only teams whose
    /// picked project is building. Keeps 18 Cloudflare accounts well under the 1,200 requests / 5 min limit.
    /// The menu's Refresh / ⌘R: always asks every picked team, never the 5s "only what's building" pass.
    private var inPushBurst: Bool { burstUntil.map { $0 > .now } ?? false }

    /// The poll loop's sleep, which `wakePolling()` cuts short (menu opened, push noticed).
    private func nap(_ seconds: Double) async {
        let task = Task { _ = try? await Task.sleep(for: .seconds(seconds)) }
        napTask = task
        await task.value
    }

    private func wakePolling() { napTask?.cancel() }

    /// Opening the menu shows current data: if it's more than a few seconds old, look now at every picked project.
    private func menuDidOpen() {
        guard !refreshing, lastAttempt.map({ Date.now.timeIntervalSince($0) > 10 }) ?? true else { return }
        lastPicked = nil
        wakePolling()
    }

    private func noticedPush() {
        burstUntil = .now.addingTimeInterval(60)
        wakePolling()
    }

    private func updatePushWatcher() {
        pushWatcher?.stop()
        pushWatcher = nil
        guard watchPushes, let pushFolder, FileManager.default.fileExists(atPath: pushFolder) else { return }
        pushWatcher = PushWatcher(folder: pushFolder) { [weak self] in self?.noticedPush() }
    }

    func refreshNow() async {
        lastPicked = nil
        await refresh(full: true)
    }

    func refresh(full: Bool = false) async {
        guard !refreshing else {
            if full { lastFull = nil } // make the next tick a full one instead of dropping the request
            return
        }
        refreshing = true
        defer { refreshing = false }
        let full = full || lastFull.map { Date.now.timeIntervalSince($0) > 600 } ?? true
        let quick = !full && (lastPicked.map { Date.now.timeIntervalSince($0) < 55 } ?? false)
        var all: [Project] = []
        var anyThrew = false
        let snapshot = accounts
        for account in snapshot {
            let mine = projects.filter { $0.accountID == account.id }
            let picked = mine.filter { selected.contains($0.id) }
            let polled = quick ? picked.filter { tracked($0).contains { $0.state == .building } } : picked
            let teams: Set<String>? = full ? nil : Set(polled.map(\.teamID))
            if (backoff[account.id] ?? .distantPast) > .now {
                anyThrew = true
                all += mine
                continue
            }
            if teams?.isEmpty == true {
                all += mine
                continue
            }
            guard let token = Keychain.get(account.id) else {
                let message = "Token missing from Keychain. Remove and re-add this account."
                accountErrors[account.id] = message
                errors[account.id] = message
                all += mine
                continue // permanent; retrying every 10s wouldn't help
            }
            do {
                let client = account.provider.client(token: token)
                var result = try await client
                    .projects(account: account, teams: teams ?? Set(picked.map(\.teamID)), discover: teams == nil)
                if full { result.projects = await autoPick(result.projects, account: account, client: client) }
                let failed = Set(result.unreachable.map(\.id))
                all += result.projects
                // Last known for teams we didn't ask or that blipped; the dedupe below keeps fresh copies first.
                all += mine.filter { p in failed.contains(p.teamID) || teams.map { !$0.contains(p.teamID) } ?? false }
                let carried = (fullUnreachable[account.id] ?? []).filter { t in teams.map { !$0.contains(t.id) } ?? false }
                fullUnreachable[account.id] = Array(Set(result.unreachable + carried))
                if full { accountErrors[account.id] = nil }
                errors[account.id] = accountErrors[account.id] ?? Self.unreachableMessage(fullUnreachable[account.id] ?? [])
                if full && errors[account.id] == nil { lastSuccessfulChecks[account.id] = .now }
            } catch {
                accountErrors[account.id] = error.localizedDescription
                errors[account.id] = error.localizedDescription
                all += mine // keep last known
                // Only blips force a full retry. A revoked token would otherwise make every account refresh every 10s.
                if !((error as? AppError)?.isAuth ?? false) { anyThrew = true }
                if (error as? AppError)?.isRateLimit == true { backoff[account.id] = .now.addingTimeInterval(60) }
                if !((error as? AppError)?.isAuth ?? false) { lastFull = nil }
            }
        }
        // An account added mid-refresh keeps the projects addAccount loaded; one removed mid-refresh stays gone.
        all += projects.filter { p in !snapshot.contains { $0.id == p.accountID } }
        let live = Set(accounts.map(\.id))
        var ids = Set<String>()
        projects = all.filter { live.contains($0.accountID) && ids.insert($0.id).inserted } // two tokens can see the same team
        errors = errors.filter { live.contains($0.key) }
        lastSuccessfulChecks = lastSuccessfulChecks.filter { live.contains($0.key) }
        lastAttempt = .now
        if full && !anyThrew { lastFull = .now } // after a failure, retry everything next tick
        if full && !anyThrew && known == nil { known = Set(projects.map(\.id)) } // first run of auto-pick: picks nothing
        if !quick { lastPicked = .now }
        Self.writeCache(projects, successfulChecks: lastSuccessfulChecks)
        notifyFinished()
        updateWobble()
    }

    /// Picks projects that appeared since the last full refresh. Vercel and Cloudflare: right away. GitHub: once the
    /// repo has a workflow run, since a token sees every repo and discovery doesn't fetch runs; so new repos get one
    /// runs call per full refresh until they have one, or until they've gone two weeks without a push.
    private func autoPick(_ fetched: [Project], account: Account, client: any ProviderClient) async -> [Project] {
        guard known != nil else { return fetched } // refresh() records the first full pass across all accounts
        let cutoff = Date.now.addingTimeInterval(-14 * 86_400)
        // Old activity means it isn't new to you, just new to us (a team the token couldn't read before).
        let new = fetched.filter { !known!.contains($0.id) && ($0.lastActive ?? .distantFuture) > cutoff }
        known!.formUnion(fetched.filter { ($0.lastActive ?? .distantFuture) <= cutoff }.map(\.id))
        guard account.provider == .github else {
            known!.formUnion(new.map(\.id))
            selected.formUnion(new.map(\.id))
            return fetched
        }
        let unpolled = new.filter { $0.latest.isEmpty }
        let polled = unpolled.isEmpty ? [] : (try? await client
            .projects(account: account, teams: Set(unpolled.map(\.teamID)), discover: false).projects) ?? []
        var withRuns = Dictionary(polled.filter { !$0.latest.isEmpty }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in new where !p.latest.isEmpty { withRuns[p.id] = p }
        known!.formUnion(withRuns.keys)
        selected.formUnion(withRuns.keys)
        return fetched.map { p in
            guard var runs = withRuns[p.id] else { return p }
            runs.activity = p.activity // the stub used for polling has no pushed_at
            return runs
        }
    }

    private static func unreachableMessage(_ teams: [TeamRef]) -> String? {
        let names = teams.map(\.name).sorted()
        if names.isEmpty { return nil }
        return names.count <= 3
            ? "Can't read \(names.joined(separator: ", ")) right now."
            : "Can't read \(names.count) teams or accounts. Check the token's permissions."
    }

    @discardableResult
    func addAccount(provider: Provider, label: String, token: String) async throws -> Account {
        let client = provider.client(token: token)
        let label = label.isEmpty ? ((try? await client.suggestedLabel()) ?? provider.name) : label
        let account = Account(label: label, provider: provider)
        let result = try await client.projects(account: account, teams: [], discover: true) // validates the token
        let fetched = result.projects
        guard Keychain.set(token, for: account.id) else { throw AppError.keychain }
        accounts.append(account)
        fullUnreachable[account.id] = result.unreachable
        errors[account.id] = Self.unreachableMessage(result.unreachable)
        let cutoff = Date.now.addingTimeInterval(-14 * 86_400)
        let recent = fetched
            .filter { ($0.lastActive ?? .distantPast) > cutoff }
            .sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
        // A GitHub token can see hundreds of repos, most without Actions; start with the 10 busiest.
        selected.formUnion(recent.prefix(provider == .github ? 10 : .max).map(\.id))
        known?.formUnion(fetched.map(\.id)) // the 14-day picks above are its first pass; the rest stay as you leave them
        projects += fetched.filter { p in !projects.contains { $0.id == p.id } }
        updateWobble()
        if provider == .github { // discovery has no runs; fetch them for the picks with a real (non-quick) pass
            lastPicked = nil
            Task { await refresh() }
        }
        return account
    }

    func removeAccount(_ account: Account) {
        Keychain.delete(account.id)
        backoff[account.id] = nil
        fullUnreachable[account.id] = nil
        accountErrors[account.id] = nil
        lastSuccessfulChecks[account.id] = nil
        accounts.removeAll { $0.id == account.id }
        // Picks stay: another token may see the same team. Unfetched ids are ignored by `rows`.
        projects.removeAll { $0.accountID == account.id }
        Self.writeCache(projects, successfulChecks: lastSuccessfulChecks) // its names and commits leave the disk now, not at the next poll
        errors[account.id] = nil
        updateWobble()
    }

    func rename(_ id: UUID, to label: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].label = label
    }

    /// Never leave an account nameless.
    func finishRename(_ id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = accounts[i].label.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[i].label = trimmed.isEmpty ? accounts[i].provider.name : trimmed
    }

    func toggleWatch(_ deployID: String) {
        if watched.remove(deployID) == nil { watched.insert(deployID) }
    }

    func toggleProductionOnly(_ projectID: String) {
        if productionOnly.remove(projectID) == nil { productionOnly.insert(projectID) }
        updateWobble()
    }

    func untrack(_ projectID: String) {
        selected.remove(projectID)
        updateWobble()
    }

    // MARK: - Menu bar wobble

    private func updateWobble() {
        let now = overall
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !animateIcon
        // Morph only when a build really landed, not when the building project was untracked or filtered out.
        if lastOverall == .building, justFinished, now == .ready || now == .failed, let now {
            freshTask?.cancel()
            freshLanding = true
            freshTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                if !Task.isCancelled { self?.freshLanding = false }
            }
            morphTask?.cancel()
            morphTask = Task { [weak self] in
                self?.justLanded = true
                defer { self?.justLanded = false }
                if !reduceMotion {
                    for frame in 0..<Glyph.morphFrames {
                        guard !Task.isCancelled else { return } // a new build started mid-morph
                        self?.morph = (now, frame)
                        try? await Task.sleep(for: .milliseconds(45))
                    }
                    self?.morph = nil
                }
                try? await Task.sleep(for: .seconds(10)) // a hidden-when-idle icon stays long enough to be seen
            }
        } else if now == .building {
            morphTask?.cancel()
            morph = nil
        }
        lastOverall = now
        justFinished = false
        let wobble = now == .building && !reduceMotion
        if wobble, wobbleTask == nil {
            wobbleTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard let self else { return }
                    wobbleFrame = (wobbleFrame + 1) % Glyph.wobbleFrames
                }
            }
        } else if !wobble {
            wobbleTask?.cancel()
            wobbleTask = nil
            wobbleFrame = 0
        }
    }

    // MARK: - Notifications

    /// Watched: always. Failed and production-ready: per the General toggles. Looks at every tracked deploy, not just
    /// each project's top row, so a deploy pushed down by a newer one still reports its finish.
    private func notifyFinished() {
        var nowSeen: [String: DeployState] = [:]
        var nowProjects: Set<String> = []
        // A project only counts as known once its deploys were fetched; a just-picked GitHub repo has none yet,
        // and its 20 old runs arriving next pass must not look like 20 fresh finishes.
        for project in projects where selected.contains(project.id) && !project.latest.isEmpty {
            nowProjects.insert(project.id)
            for deploy in tracked(project) {
                nowSeen[deploy.id] = deploy.state
                guard deploy.state != .building else { continue }
                if deploy.state == .canceled { // ignored, like SCOPE says; just drop any watch
                    watched.remove(deploy.id)
                    continue
                }
                // Was building last pass, or is brand new on a project we already knew (built between polls).
                // Watched deploys were building by definition; survives a forgetSeen() mid-build.
                let finished = watched.contains(deploy.id) || seen[deploy.id] == .building || (seen[deploy.id] == nil && seenProjects.contains(project.id))
                guard finished else { continue }
                justFinished = true
                let wasWatched = watched.remove(deploy.id) != nil
                if wasWatched || (deploy.state == .failed && notifyFailed) || (deploy.state == .ready && deploy.isProduction && notifyReady) {
                    post(deploy)
                }
            }
        }
        seen = nowSeen
        seenProjects = nowProjects
        watched.formIntersection(nowSeen.keys) // drop watches on deploys that fell out of view
    }

    /// Settings changes swap which deploys are tracked; don't notify about the swap.
    private func forgetSeen() {
        seen = [:]
        seenProjects = []
    }

    private func post(_ deploy: Deploy) {
        let content = UNMutableNotificationContent()
        content.title = deploy.projectName
        // The menu's voice ("Yep. All deployed."): a light touch on good news, the next step on bad news.
        content.subtitle = deploy.state == .failed ? "Build failed. Click to see why." : "Yep, it's live."
        // Commit subject when there is one; wrangler and manual redeploys have none, so say where it went instead.
        let subject = deploy.message?.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        // GitHub runs have no preview/production target, only branches, so name the target for the others alone.
        let target = deploy.provider == .github ? nil : deploy.isProduction ? "production" : "preview"
        let place = [deploy.branch, target].compactMap { $0 }.joined(separator: " · ")
        content.body = subject.isEmpty ? place : subject
        content.threadIdentifier = deploy.projectID // a busy project's deploys stack together in Notification Center
        if let url = deploy.url { content.userInfo = ["url": url.absoluteString] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: deploy.id, content: content, trigger: nil))
    }

    // MARK: - Persistence (no secrets here, tokens are in Keychain)

    private struct Cache: Codable {
        let savedAt: Date
        let projects: [Project]
        var successfulChecks: [UUID: Date]?
    }

    private static let cacheURL = URL.applicationSupportDirectory.appending(path: "DeployedYet/projects.json")

    private static func readCache() -> Cache? {
        (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    }

    // ponytail: rewrites the whole file each poll (~200KB for 500 projects). Diff or debounce if that ever shows up.
    private static func writeCache(_ projects: [Project], successfulChecks: [UUID: Date]) {
        guard let data = try? JSONEncoder().encode(Cache(savedAt: .now, projects: projects, successfulChecks: successfulChecks)) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

/// Clicking a notification opens the deploy. Banners show even while the menu is open.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string), url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }
}
