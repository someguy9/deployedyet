import Foundation
import Observation

@MainActor @Observable
final class Analytics {
    static let shared = Analytics()

    enum Consent: String {
        case undecided, enabled, disabled
    }

    enum Setting: String {
        case trackPreviews = "track_previews"
        case notifyFailed = "notify_failed"
        case notifyReady = "notify_ready"
        case watchPushes = "watch_pushes"
        case animateIcon = "animate_icon"
        case iconOnlyWhenBusy = "icon_only_when_busy"
        case productionOnly = "production_only"
        case launchAtLogin = "launch_at_login"
    }

    enum Event {
        case menuOpened, settingsOpened, refreshRequested, deploymentOpened
        case accountConnectionStarted(Provider), accountConnected(Provider)
        case accountConnectionFailed(Provider), accountRemoved(Provider)
        case projectsChanged, deploymentWatchChanged(Bool)
        case settingChanged(Setting, Bool)

        var name: String {
            switch self {
            case .menuOpened: "menu_opened"
            case .settingsOpened: "settings_opened"
            case .refreshRequested: "refresh_requested"
            case .deploymentOpened: "deployment_opened"
            case .accountConnectionStarted: "account_connection_started"
            case .accountConnected: "account_connected"
            case .accountConnectionFailed: "account_connection_failed"
            case .accountRemoved: "account_removed"
            case .projectsChanged: "project_tracking_changed"
            case .deploymentWatchChanged: "deployment_watch_changed"
            case .settingChanged: "setting_changed"
            }
        }

        var properties: [String: Any] {
            switch self {
            case .accountConnectionStarted(let provider), .accountConnected(let provider),
                 .accountConnectionFailed(let provider), .accountRemoved(let provider):
                ["provider": provider.rawValue]
            case .deploymentWatchChanged(let enabled): ["enabled": enabled]
            case .settingChanged(let setting, let enabled): ["setting": setting.rawValue, "enabled": enabled]
            default: [:]
            }
        }
    }

    struct Snapshot {
        let accounts: Int
        let projects: Int
    }

    struct Configuration {
        let token: String
        let host: URL
        let allowDebug: Bool

        static func load(bundle: Bundle = .main) -> Self? {
            guard let url = bundle.url(forResource: "AnalyticsConfig", withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let token = values["PostHogProjectToken"] as? String,
                  token.hasPrefix("phc_"), token.count > 12,
                  let hostString = values["PostHogHost"] as? String,
                  let host = URL(string: hostString),
                  host.scheme == "https", host.user == nil, host.password == nil,
                  host.query == nil, host.fragment == nil,
                  host.path.isEmpty || host.path == "/",
                  ["us.i.posthog.com", "eu.i.posthog.com"].contains(host.host) else { return nil }
            return Self(token: token, host: host, allowDebug: values["AllowDebugAnalytics"] as? Bool ?? false)
        }
    }

    private struct Pending {
        let data: Data
        let dailyKey: String?
        let day: String
    }

    private(set) var consent: Consent
    private(set) var noticeDismissed: Bool
    let configured: Bool
    let debugDisabled: Bool
    var canSend: Bool { configured && !debugDisabled && consent == .enabled }
    var needsChoice: Bool { canSend && !noticeDismissed }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let configuration: Configuration?
    @ObservationIgnored private let sessionConfiguration: () -> URLSessionConfiguration
    @ObservationIgnored private var snapshot: (() -> Snapshot)?
    @ObservationIgnored private var installationID: String?
    @ObservationIgnored private var queue: [Pending] = []
    @ObservationIgnored private var pendingDaily: Set<String> = []
    @ObservationIgnored private var dailyAttempts: [String: Date] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var sleeping = false

    init(defaults: UserDefaults = .standard, configuration: Configuration? = Configuration.load(),
         sessionConfiguration: @escaping () -> URLSessionConfiguration = { .ephemeral }) {
        self.defaults = defaults
        self.configuration = configuration
        self.sessionConfiguration = sessionConfiguration
        configured = configuration != nil
        #if DEBUG
        debugDisabled = configuration?.allowDebug != true
        #else
        debugDisabled = false
        #endif
        let savedConsent = defaults.string(forKey: "analytics.consent").flatMap(Consent.init(rawValue:))
        consent = savedConsent == .disabled ? .disabled : .enabled
        noticeDismissed = defaults.bool(forKey: "analytics.noticeDismissed")
        if consent != .enabled { clearIdentity() }
    }

    func start(snapshot: @escaping () -> Snapshot) {
        self.snapshot = snapshot
        resume()
    }

    func setConsent(_ enabled: Bool) {
        noticeDismissed = true
        defaults.set(true, forKey: "analytics.noticeDismissed")
        let next: Consent = enabled ? .enabled : .disabled
        guard consent != next else { return }
        stop()
        consent = next
        defaults.set(next.rawValue, forKey: "analytics.consent")
        if enabled {
            resume()
            enqueue("analytics_enabled")
            daily("app_daily_active")
        } else {
            clearIdentity()
        }
    }

    func capture(_ event: Event) {
        guard canSend else { return }
        daily("app_daily_active")
        enqueue(event.name, properties: event.properties)
    }

    func setSleeping(_ sleeping: Bool) {
        self.sleeping = sleeping
        if !sleeping { tick() }
    }

    func stop() {
        generation = UUID()
        heartbeat?.cancel()
        heartbeat = nil
        worker?.cancel()
        worker = nil
        session?.invalidateAndCancel()
        session = nil
        queue.removeAll()
        pendingDaily.removeAll()
        dailyAttempts.removeAll()
    }

    private func resume() {
        guard canSend, heartbeat == nil else { return }
        installationID = defaults.string(forKey: "analytics.installationID") ?? UUID().uuidString
        defaults.set(installationID, forKey: "analytics.installationID")
        let config = sessionConfiguration()
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config, delegate: AnalyticsRedirectGuard(), delegateQueue: nil)
        enqueue("analytics_session_started")
        tick()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard canSend, !sleeping else { return }
        daily("app_daily_running")
        if let snapshot = snapshot?() {
            daily("app_daily_snapshot", properties: [
                "account_count_bucket": Self.bucket(snapshot.accounts),
                "tracked_project_count_bucket": Self.bucket(snapshot.projects),
            ])
        }
    }

    private func daily(_ name: String, properties: [String: Any] = [:]) {
        let day = Self.day()
        let key = "analytics.daily.\(name)"
        guard defaults.string(forKey: key) != day, !pendingDaily.contains(key),
              dailyAttempts[key].map({ Date.now.timeIntervalSince($0) >= 300 }) ?? true else { return }
        if enqueue(name, properties: properties, dailyKey: key) {
            dailyAttempts[key] = .now
        }
    }

    @discardableResult
    private func enqueue(_ name: String, properties: [String: Any] = [:], dailyKey: String? = nil) -> Bool {
        guard canSend, let configuration, let installationID, queue.count < 50 else { return false }
        var values = properties
        values["$process_person_profile"] = false
        values["$geoip_disable"] = true
        values["$ip"] = "0.0.0.0"
        values["app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        values["app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        values["macos_major_version"] = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        values["schema_version"] = 1
        #if DEBUG
        values["environment"] = "development"
        #else
        values["environment"] = "production"
        #endif
        let payload: [String: Any] = [
            "api_key": configuration.token,
            "distinct_id": installationID,
            "event": name,
            "properties": values,
            "timestamp": ISO8601DateFormatter().string(from: .now),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        queue.append(Pending(data: data, dailyKey: dailyKey, day: Self.day()))
        if let dailyKey { pendingDaily.insert(dailyKey) }
        if worker == nil {
            let generation = generation
            worker = Task { [weak self] in await self?.drain(generation: generation) }
        }
        return true
    }

    private func drain(generation: UUID) async {
        while !Task.isCancelled, self.generation == generation, canSend, !queue.isEmpty,
              let configuration, let session {
            let pending = queue.removeFirst()
            var request = URLRequest(url: configuration.host.appendingPathComponent("i/v0/e/"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = pending.data
            let response = try? await session.data(for: request)
            guard self.generation == generation, !Task.isCancelled else { return }
            if let key = pending.dailyKey {
                pendingDaily.remove(key)
                if let http = response?.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    defaults.set(pending.day, forKey: key)
                    dailyAttempts.removeValue(forKey: key)
                }
            }
        }
        if self.generation == generation { worker = nil }
    }

    private func clearIdentity() {
        installationID = nil
        defaults.removeObject(forKey: "analytics.installationID")
        for name in ["app_daily_active", "app_daily_running", "app_daily_snapshot"] {
            defaults.removeObject(forKey: "analytics.daily.\(name)")
        }
    }

    private static func day() -> String {
        String(ISO8601DateFormatter().string(from: .now).prefix(10))
    }

    private static func bucket(_ count: Int) -> String {
        switch count {
        case ...0: "0"
        case 1: "1"
        case 2...5: "2–5"
        case 6...10: "6–10"
        default: "11+"
        }
    }
}

private final class AnalyticsRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
